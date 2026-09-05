// Reference verifier for the randomness beacon.
//
//     dcc64 verify.dpr
//     verify.exe emission.jws [public-key-hex]
//
// SHA-256, HMAC, base64url and JSON come from the standard library. Only
// Ed25519 needs OpenSSL:
//
//     libcrypto-3-x64.dll   https://openssl-library.org
//
// Put it next to the executable. Without it the verifier answers UNVERIFIABLE
// for the signature and still checks everything else.
//
// It reads a file, not a URL:
//     curl -s https://.../1730-emission.jws -o e.jws && verify e.jws
//
// It does not check drand's BLS signature: that needs a pairing library.
// Compare round.randomness against https://api.drand.sh/public/<round>
// yourself — the round travels whole inside the file.
program verify;

{$APPTYPE CONSOLE}
{$R-}

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Hash,
  System.IOUtils,
  System.JSON,
  System.NetEncoding,
{$IFDEF MSWINDOWS}
  Winapi.Windows;
{$ELSE}
  Posix.Dlfcn;
{$ENDIF}

const
  HKDF_BLOCK = 64;

type
  TBytesArray = array of TBytes;
  TLongArray = array of Int64;

  TBlock = record
    Mold: string;
    Count, Min, Max: Int64;
  end;

  TBlocks = array of TBlock;

  // Delivers deterministic bytes on demand. It stretches itself: the counter
  // goes inside the HKDF info so every stretch is independent of the previous.
  TStream_ = class
  private
    FSeed, FPublic, FContext, FBuf: TBytes;
    FPos: Integer;
  public
    constructor Create(const ASeed, APublic, AContext: TBytes);
    function NextByte: Byte;
    function Integer_(ALimit: Int64): Int64;
  end;

// --- Encoding --------------------------------------------------------------

function FromHex(const AHex: string): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Length(AHex) div 2);
  for I := 0 to High(Result) do
    Result[I] := StrToInt('$' + Copy(AHex, I * 2 + 1, 2));
end;

function ToHex(const ABytes: TBytes): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ABytes) do
    Result := Result + LowerCase(IntToHex(ABytes[I], 2));
end;

function FromB64Url(const AText: string): TBytes;
var
  S: string;
begin
  S := StringReplace(AText, '-', '+', [rfReplaceAll]);
  S := StringReplace(S, '_', '/', [rfReplaceAll]);
  while Length(S) mod 4 <> 0 do
    S := S + '=';
  Result := TNetEncoding.Base64.DecodeStringToBytes(S);
end;

// --- Crypto ----------------------------------------------------------------

// El enum va CALIFICADO a proposito: Pascal no distingue mayusculas, asi que
// una funcion llamada Sha256 tapa al identificador SHA256 del enum y el error
// que da es "Not enough actual parameters", que no dice nada.
function Sha256(const AData: TBytes): TBytes;
var
  H: THashSHA2;
begin
  // GetHashBytes solo acepta string o TStream, asi que para TBytes va la API
  // de instancia. Pasarle un string obligaria a decidir una codificacion, y
  // la R2 dice que los hashes van sobre los BYTES.
  H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  H.Update(AData);
  Result := H.HashAsBytes;
end;

// HKDF-SHA256, RFC 5869, both stages.
function Hkdf(const AIkm, ASalt, AInfo: TBytes; ALength: Integer): TBytes;
var
  Prk, Block, Input: TBytes;
  I: Byte;
  Total: Integer;
begin
  Prk := THashSHA2.GetHMACAsBytes(AIkm, ASalt, THashSHA2.TSHA2Version.SHA256);

  SetLength(Result, 0);
  SetLength(Block, 0);
  Total := 0;
  I := 1;
  while Total < ALength do
  begin
    SetLength(Input, Length(Block) + Length(AInfo) + 1);
    if Length(Block) > 0 then
      Move(Block[0], Input[0], Length(Block));
    if Length(AInfo) > 0 then
      Move(AInfo[0], Input[Length(Block)], Length(AInfo));
    Input[Length(Input) - 1] := I;

    Block := THashSHA2.GetHMACAsBytes(Input, Prk, THashSHA2.TSHA2Version.SHA256);

    SetLength(Result, Total + Length(Block));
    Move(Block[0], Result[Total], Length(Block));
    Inc(Total, Length(Block));
    Inc(I);
  end;
  SetLength(Result, ALength);
end;

// --- The byte stream -------------------------------------------------------

constructor TStream_.Create(const ASeed, APublic, AContext: TBytes);
begin
  inherited Create;
  FSeed := ASeed;
  FPublic := APublic;
  FContext := AContext;
  SetLength(FBuf, 0);
  FPos := 0;
end;

function TStream_.NextByte: Byte;
var
  Info, Block: TBytes;
  Tail: TBytes;
  Old: Integer;
begin
  if FPos >= Length(FBuf) then
  begin
    Tail := TEncoding.UTF8.GetBytes('|' + IntToStr(Length(FBuf)));
    SetLength(Info, Length(FContext) + Length(Tail));
    if Length(FContext) > 0 then
      Move(FContext[0], Info[0], Length(FContext));
    Move(Tail[0], Info[Length(FContext)], Length(Tail));

    Block := Hkdf(FSeed, FPublic, Info, HKDF_BLOCK);
    Old := Length(FBuf);
    SetLength(FBuf, Old + Length(Block));
    Move(Block[0], FBuf[Old], Length(Block));
  end;
  Result := FBuf[FPos];
  Inc(FPos);
end;

// Uniform value in [0,limit) with no modulo bias: values above the last whole
// multiple of limit are discarded and drawn again.
function TStream_.Integer_(ALimit: Int64): Int64;
var
  Width, I: Integer;
  Space, Cut, V: Int64;
begin
  if ALimit <= 1 then
    Exit(0);

  Width := 1;
  Space := 256;
  while Space < ALimit do
  begin
    Inc(Width);
    Space := Space * 256;
  end;
  Cut := (Space div ALimit) * ALimit;

  while True do
  begin
    V := 0;
    for I := 1 to Width do
      V := V * 256 + NextByte;
    if V < Cut then
      Exit(V mod ALimit);
  end;
end;

// --- Derivation ------------------------------------------------------------

// Draws k distinct values in the order they come out, with a partial
// Fisher-Yates over a sparse map.
function SampleWithoutReplacement(AStream: TStream_; AUniverse, ACount, AMin: Int64): TLongArray;
var
  Moved: TDictionary<Int64, Int64>;
  I, J, Vi, Vj: Int64;
begin
  Moved := TDictionary<Int64, Int64>.Create;
  try
    SetLength(Result, ACount);
    for I := 0 to ACount - 1 do
    begin
      J := I + AStream.Integer_(AUniverse - I);

      if not Moved.TryGetValue(J, Vj) then
        Vj := J;
      if not Moved.TryGetValue(I, Vi) then
        Vi := I;
      Moved.AddOrSetValue(J, Vi);
      Moved.AddOrSetValue(I, Vj);

      Result[I] := AMin + Vj;
    end;
  finally
    Moved.Free;
  end;
end;

procedure SortValues(var AValues: TLongArray);
var
  I, J: Integer;
  T: Int64;
begin
  for I := 1 to High(AValues) do
  begin
    J := I;
    while (J > 0) and (AValues[J] < AValues[J - 1]) do
    begin
      T := AValues[J];
      AValues[J] := AValues[J - 1];
      AValues[J - 1] := T;
      Dec(J);
    end;
  end;
end;

function DeriveBlock(AStream: TStream_; const ABlock: TBlock): TLongArray;
var
  Universe, Count, I: Int64;
begin
  Universe := ABlock.Max - ABlock.Min + 1;
  Count := ABlock.Count;
  if Count = 0 then
    Count := 1;

  if ABlock.Mold = 'discrete_uniform' then
  begin
    SetLength(Result, 1);
    Result[0] := ABlock.Min + AStream.Integer_(Universe);
    Exit;
  end;

  if ABlock.Mold = 'sample_without_replacement' then
  begin
    Result := SampleWithoutReplacement(AStream, Universe, Count, ABlock.Min);
    SortValues(Result);
    Exit;
  end;

  if ABlock.Mold = 'permutation' then
    Exit(SampleWithoutReplacement(AStream, Universe, Count, ABlock.Min));

  if (ABlock.Mold = 'uniform_vector_with_replacement') or (ABlock.Mold = 'random_matrix') then
  begin
    SetLength(Result, Count);
    for I := 0 to Count - 1 do
      Result[I] := ABlock.Min + AStream.Integer_(Universe);
    Exit;
  end;

  // min and max already carry the scale, so the span is read straight off the
  // file. Multiplying again is the classic reimplementation bug.
  if ABlock.Mold = 'truncated_continuous' then
  begin
    SetLength(Result, 1);
    Result[0] := ABlock.Min + AStream.Integer_(ABlock.Max - ABlock.Min + 1);
    Exit;
  end;

  raise Exception.Create('unknown mold ' + ABlock.Mold);
end;

// A variant is published in one of two shapes, and this is the first thing a
// reimplementation gets wrong:
//
//   - composite carries an explicit "blocks" array
//   - every other group carries its parameters FLAT, and the mold is the
//     GROUP NAME, not a field
//
// Two more traps in the flat shape: random_matrix carries rows/cols instead of
// count, and truncated_continuous publishes min/max already multiplied by
// scale.
function BlocksOf(const AGroup: string; AVariant: TJSONObject): TBlocks;
var
  Arr: TJSONArray;
  I: Integer;
  Item: TJSONObject;
begin
  if AGroup = 'composite' then
  begin
    Arr := AVariant.GetValue<TJSONArray>('blocks');
    SetLength(Result, Arr.Count);
    for I := 0 to Arr.Count - 1 do
    begin
      Item := Arr.Items[I] as TJSONObject;
      Result[I].Mold := Item.GetValue<string>('mold');
      Result[I].Count := Item.GetValue<Int64>('count', 1);
      Result[I].Min := Item.GetValue<Int64>('min');
      Result[I].Max := Item.GetValue<Int64>('max');
    end;
    Exit;
  end;

  SetLength(Result, 1);
  Result[0].Mold := AGroup;
  Result[0].Min := AVariant.GetValue<Int64>('min');
  Result[0].Max := AVariant.GetValue<Int64>('max');
  if AGroup = 'random_matrix' then
    Result[0].Count := AVariant.GetValue<Int64>('rows') * AVariant.GetValue<Int64>('cols')
  else
    Result[0].Count := AVariant.GetValue<Int64>('count', 1);
end;

function JoinValues(const AValues: TLongArray): string;
var
  I: Integer;
begin
  Result := '[';
  for I := 0 to High(AValues) do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + IntToStr(AValues[I]);
  end;
  Result := Result + ']';
end;

// Renders the result the way the file publishes it: a scalar, a list, a list
// of rows, or one list per block.
function Shape(const AName: string; const ASpec: TBlocks;
  const ABlocks: array of TLongArray): string;
var
  I, R, C: Integer;
  Rows, Cols, Total: Integer;
  Flat: TLongArray;
begin
  if Length(ASpec) > 1 then
  begin
    Result := '[';
    for I := 0 to High(ABlocks) do
    begin
      if I > 0 then
        Result := Result + ',';
      Result := Result + JoinValues(ABlocks[I]);
    end;
    Exit(Result + ']');
  end;

  Flat := ABlocks[0];

  if (ASpec[0].Mold = 'discrete_uniform') or (ASpec[0].Mold = 'truncated_continuous') then
    Exit(IntToStr(Flat[0]));

  if ASpec[0].Mold = 'random_matrix' then
  begin
    Total := Length(Flat);
    Rows := 1;
    Cols := Total;
    // The matrix shape lives in the variant name: m-<rows>x<cols>
    if (Length(AName) > 2) and (Copy(AName, 1, 2) = 'm-') then
    begin
      I := Pos('x', AName);
      if I > 0 then
      begin
        Rows := StrToIntDef(Copy(AName, 3, I - 3), 1);
        Cols := StrToIntDef(Copy(AName, I + 1, Length(AName)), Total);
        if (Rows <= 0) or (Cols <= 0) or (Rows * Cols <> Total) then
        begin
          Rows := 1;
          Cols := Total;
        end;
      end;
    end;

    Result := '[';
    for R := 0 to Rows - 1 do
    begin
      if R > 0 then
        Result := Result + ',';
      Result := Result + '[';
      for C := 0 to Cols - 1 do
      begin
        if C > 0 then
          Result := Result + ',';
        Result := Result + IntToStr(Flat[R * Cols + C]);
      end;
      Result := Result + ']';
    end;
    Exit(Result + ']');
  end;

  Result := JoinValues(Flat);
end;

// --- Ed25519 through OpenSSL ----------------------------------------------
//
// Loaded at run time on purpose: without the library the verifier still checks
// everything else and says UNVERIFIABLE for the signature. A missing DLL is
// not a reason to answer "false".

type
  TEVP_PKEY_new_raw_public_key = function(AType: Integer; AEngine: Pointer;
    const AKey: PByte; ALen: NativeUInt): Pointer; cdecl;
  TEVP_MD_CTX_new = function: Pointer; cdecl;
  TEVP_MD_CTX_free = procedure(ACtx: Pointer); cdecl;
  TEVP_DigestVerifyInit = function(ACtx: Pointer; APctx: Pointer; AType: Pointer;
    AEngine: Pointer; APkey: Pointer): Integer; cdecl;
  TEVP_DigestVerify = function(ACtx: Pointer; const ASig: PByte; ASigLen: NativeUInt;
    const AData: PByte; ADataLen: NativeUInt): Integer; cdecl;
  TEVP_PKEY_free = procedure(APkey: Pointer); cdecl;

const
  EVP_PKEY_ED25519 = 1087;

var
  GLib: {$IFDEF MSWINDOWS}HMODULE{$ELSE}Pointer{$ENDIF} = {$IFDEF MSWINDOWS}0{$ELSE}nil{$ENDIF};
  GNewRawPublicKey: TEVP_PKEY_new_raw_public_key;
  GCtxNew: TEVP_MD_CTX_new;
  GCtxFree: TEVP_MD_CTX_free;
  GVerifyInit: TEVP_DigestVerifyInit;
  GVerify: TEVP_DigestVerify;
  GPkeyFree: TEVP_PKEY_free;

function Cargada: Boolean; inline;
begin
{$IFDEF MSWINDOWS}
  Result := GLib <> 0;
{$ELSE}
  Result := GLib <> nil;
{$ENDIF}
end;

function Simbolo(const AName: string): Pointer;
begin
{$IFDEF MSWINDOWS}
  Result := GetProcAddress(GLib, PChar(AName));
{$ELSE}
  Result := dlsym(GLib, PAnsiChar(AnsiString(AName)));
{$ENDIF}
end;

function LoadOpenSsl: Boolean;
const
  NAMES: array [0 .. 3] of string = ('libcrypto-3-x64.dll', 'libcrypto-3.dll', 'libcrypto.so.3',
    'libcrypto.dll');
var
  I: Integer;
begin
  if Cargada then
    Exit(True);

  for I := 0 to High(NAMES) do
  begin
{$IFDEF MSWINDOWS}
    GLib := LoadLibrary(PChar(NAMES[I]));
    if GLib <> 0 then
      Break;
{$ELSE}
    GLib := dlopen(PAnsiChar(AnsiString(NAMES[I])), RTLD_NOW);
    if GLib <> nil then
      Break;
{$ENDIF}
  end;
  if not Cargada then
    Exit(False);

  @GNewRawPublicKey := Simbolo('EVP_PKEY_new_raw_public_key');
  @GCtxNew := Simbolo('EVP_MD_CTX_new');
  @GCtxFree := Simbolo('EVP_MD_CTX_free');
  @GVerifyInit := Simbolo('EVP_DigestVerifyInit');
  @GVerify := Simbolo('EVP_DigestVerify');
  @GPkeyFree := Simbolo('EVP_PKEY_free');

  Result := Assigned(GNewRawPublicKey) and Assigned(GCtxNew) and Assigned(GVerifyInit) and
    Assigned(GVerify);
end;

function VerifyEd25519(const AKey, AMsg, ASig: TBytes): Boolean;
var
  Pkey, Ctx: Pointer;
begin
  Result := False;
  Pkey := GNewRawPublicKey(EVP_PKEY_ED25519, nil, @AKey[0], Length(AKey));
  if Pkey = nil then
    Exit;
  try
    Ctx := GCtxNew;
    if Ctx = nil then
      Exit;
    try
      if GVerifyInit(Ctx, nil, nil, nil, Pkey) <> 1 then
        Exit;
      Result := GVerify(Ctx, @ASig[0], Length(ASig), @AMsg[0], Length(AMsg)) = 1;
    finally
      GCtxFree(Ctx);
    end;
  finally
    GPkeyFree(Pkey);
  end;
end;

// --- Main ------------------------------------------------------------------

procedure Fail(const AKind, AWhy: string; ACode: Integer);
begin
  Writeln;
  Writeln(AKind + ': ' + AWhy);
  Halt(ACode);
end;

procedure NotVerified(const AWhy: string);
begin
  Fail('NOT VERIFIED', AWhy, 1);
end;

procedure Unverifiable(const AWhy: string);
begin
  Fail('UNVERIFIABLE', AWhy, 3);
end;

procedure Run;
var
  Raw, HeaderTxt, PayloadTxt, Version, Name, Got, Want: string;
  D1, D2, I: Integer;
  Header, Payload, Variants, Group, Variant: TJSONObject;
  GroupPair, VariantPair: TJSONPair;
  Seed, PublicValue: TBytes;
  Round_: Int64;
  Spec: TBlocks;
  Blocks: array of TLongArray;
  S: TStream_;
  Checked, Failed: Integer;
begin
  if ParamCount < 1 then
  begin
    Writeln('usage: verify <file.jws> [public-key-hex]');
    Halt(2);
  end;

  try
    Raw := Trim(TFile.ReadAllText(ParamStr(1)));
  except
    on E: Exception do
      Unverifiable('cannot read the file: ' + E.Message);
  end;

  D1 := Pos('.', Raw);
  D2 := LastDelimiter('.', Raw);
  if (D1 = 0) or (D1 = D2) then
    NotVerified('expected 3 dot-separated parts');

  HeaderTxt := TEncoding.UTF8.GetString(FromB64Url(Copy(Raw, 1, D1 - 1)));
  PayloadTxt := TEncoding.UTF8.GetString(FromB64Url(Copy(Raw, D1 + 1, D2 - D1 - 1)));

  Header := TJSONObject.ParseJSONValue(HeaderTxt) as TJSONObject;
  Payload := TJSONObject.ParseJSONValue(PayloadTxt) as TJSONObject;

  Version := Payload.GetValue<string>('version');
  Round_ := Payload.GetValue<Int64>('drand_round');

  Writeln(Format('file      : %s turn %s, version %s, drand round %d',
    [Payload.GetValue<string>('type'), Payload.GetValue<string>('utc_turn'), Version, Round_]));
  Writeln('key id    : ' + Header.GetValue<string>('kid'));

  // 1. Signature, over the RAW text: re-serializing the JSON changes the bytes
  // and breaks a signature that is perfectly valid.
  if ParamCount >= 2 then
  begin
    if not LoadOpenSsl then
      Unverifiable('libcrypto not found: put libcrypto-3-x64.dll next to the executable');
    if not VerifyEd25519(FromHex(Trim(ParamStr(2))),
      TEncoding.UTF8.GetBytes(Copy(Raw, 1, D2 - 1)), FromB64Url(Copy(Raw, D2 + 1, MaxInt))) then
      NotVerified('the Ed25519 signature does not verify');
    Writeln('signature : OK');
  end
  else
    Writeln('signature : SKIPPED, no public key given');

  // 2. The revealed seed must hash to what was committed.
  Seed := FromHex(Payload.GetValue<string>('seed'));
  if ToHex(Sha256(Seed)) <> Payload.GetValue<string>('seed_sha256') then
    NotVerified('SHA-256 of the seed does not match seed_sha256');
  Writeln('seed      : OK, matches its own hash');

  PublicValue := FromHex(Payload.GetValue<TJSONObject>('round').GetValue<string>('randomness'));

  // 3. Every number, reproduced from the seed and the round.
  Checked := 0;
  Failed := 0;
  Variants := Payload.GetValue<TJSONObject>('variants');

  for GroupPair in Variants do
  begin
    Group := GroupPair.JsonValue as TJSONObject;
    for VariantPair in Group do
    begin
      Name := VariantPair.JsonString.Value;
      Variant := VariantPair.JsonValue as TJSONObject;
      Spec := BlocksOf(GroupPair.JsonString.Value, Variant);

      SetLength(Blocks, Length(Spec));
      for I := 0 to High(Spec) do
      begin
        S := TStream_.Create(Seed, PublicValue,
          TEncoding.UTF8.GetBytes(Format('%s|%s|%d|b%d', [Version, Name, Round_, I])));
        try
          Blocks[I] := DeriveBlock(S, Spec[I]);
        finally
          S.Free;
        end;
      end;

      Got := Shape(Name, Spec, Blocks);
      Want := Variant.GetValue<TJSONValue>('result').ToJSON;
      Want := StringReplace(Want, ' ', '', [rfReplaceAll]);

      if Got <> Want then
      begin
        Inc(Failed);
        Writeln(Format('  %-24s MISMATCH', [Name]));
        Writeln('     expected ' + Want);
        Writeln('     computed ' + Got);
        Continue;
      end;
      Inc(Checked);
    end;
  end;

  if Failed > 0 then
    NotVerified(Format('%d of %d variants do not reproduce', [Failed, Checked + Failed]));
  Writeln(Format('numbers   : OK, %d variants reproduced', [Checked]));

  Writeln;
  Writeln('VERIFIED');
end;

begin
  try
    Run;
  except
    on E: Exception do
      Unverifiable(E.ClassName + ': ' + E.Message);
  end;
end.
