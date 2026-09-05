// Reference verifier for the randomness beacon.
//
// Standard library only. No dependencies, nothing to install.
//
//	go run . emission.jws
//	go run . https://.../2026/08/29/1730-emission.jws
//
// It answers one of three things, and the third one is not a failure:
//
//	VERIFIED      signature, commitment and every number reproduce
//	NOT VERIFIED  something does not match. The file is not what it claims
//	UNVERIFIABLE  the check could not be completed (no key, no network)
package main

import (
	"crypto/ed25519"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	HKDF_BLOCK   = 64
	DRAND_RELAY  = "https://drand.cloudflare.com"
	HTTP_TIMEOUT = 20 * time.Second
)

type Emission struct {
	Version    string `json:"version"`
	Type       string `json:"type"`
	UTCTurn    string `json:"utc_turn"`
	Seed       string `json:"seed"`
	SeedHash   string `json:"seed_sha256"`
	DrandRound uint64 `json:"drand_round"`
	Round      struct {
		Round      uint64 `json:"round"`
		Randomness string `json:"randomness"`
	} `json:"round"`
	Variants map[string]map[string]json.RawMessage `json:"variants"`
}

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
type Variant struct {
	Blocks []Block         `json:"blocks"`
	Count  int             `json:"count"`
	Min    int             `json:"min"`
	Max    int             `json:"max"`
	Rows   int             `json:"rows"`
	Cols   int             `json:"cols"`
	Result json.RawMessage `json:"result"`
}

type Block struct {
	Mold  string `json:"mold"`
	Count int    `json:"count"`
	Min   int    `json:"min"`
	Max   int    `json:"max"`
}

// blocksOf normalizes both shapes into the same list of blocks.
func blocksOf(group string, v Variant) []Block {
	if group == "composite" {
		return v.Blocks
	}
	count := v.Count
	if group == "random_matrix" {
		count = v.Rows * v.Cols
	}
	b := Block{Mold: group, Count: count, Min: v.Min, Max: v.Max}
	return []Block{b}
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("usage: verifier <file.jws|url> [public-key-hex]")
		os.Exit(2)
	}

	raw, err := read(os.Args[1])
	if err != nil {
		unverifiable("cannot read the file: %v", err)
	}

	header, payload, signature, err := splitJWS(raw)
	if err != nil {
		notVerified("malformed file: %v", err)
	}

	var em Emission
	if err := json.Unmarshal(payload, &em); err != nil {
		notVerified("unreadable payload: %v", err)
	}
	fmt.Printf("file      : %s turn %s, version %s, drand round %d\n",
		em.Type, em.UTCTurn, em.Version, em.DrandRound)

	// 1. Signature. It is checked over the RAW text: re-serializing the JSON
	// changes the bytes and breaks a signature that is perfectly valid.
	if key := publicKey(header); key != nil {
		signed := raw[:strings.LastIndex(raw, ".")]
		if !ed25519.Verify(key, []byte(signed), signature) {
			notVerified("the Ed25519 signature does not verify")
		}
		fmt.Println("signature : OK")
	} else {
		fmt.Println("signature : SKIPPED, no public key given")
	}

	// 2. The revealed seed must hash to what was committed.
	seed, err := hex.DecodeString(em.Seed)
	if err != nil {
		notVerified("the seed is not valid hex")
	}
	if sum := sha256.Sum256(seed); hex.EncodeToString(sum[:]) != em.SeedHash {
		notVerified("SHA-256 of the seed does not match seed_sha256")
	}
	fmt.Println("seed      : OK, matches its own hash")

	// 3. The public value comes from drand, not from us. Ask them.
	if _, err := hex.DecodeString(em.Round.Randomness); err != nil {
		notVerified("randomness is not valid hex")
	}
	if remote, err := drandRandomness(em.DrandRound); err != nil {
		fmt.Printf("drand     : SKIPPED, %v\n", err)
	} else if remote != em.Round.Randomness {
		notVerified("drand round %d carries a different randomness", em.DrandRound)
	} else {
		fmt.Println("drand     : OK, round", em.DrandRound, "carries this randomness")
	}

	// 4. Every number, reproduced from the seed and the round.
	checked, failed := 0, 0
	for group, variants := range em.Variants {
		for name, raw := range variants {
			var v Variant
			if err := json.Unmarshal(raw, &v); err != nil {
				notVerified("%s: %v", name, err)
			}
			got, err := derive(em, name, blocksOf(group, v))
			if err != nil {
				notVerified("%s: %v", name, err)
			}
			want := strings.Join(strings.Fields(string(v.Result)), "")
			if got != want {
				failed++
				fmt.Printf("  %-24s MISMATCH\n     expected %s\n     computed %s\n", name, want, got)
				continue
			}
			checked++
		}
	}
	if failed > 0 {
		notVerified("%d of %d variants do not reproduce", failed, checked+failed)
	}
	fmt.Printf("numbers   : OK, %d variants reproduced\n", checked)

	fmt.Println()
	fmt.Println("VERIFIED")
}

// derive recomputes one variant and returns it in the published shape.
func derive(em Emission, name string, spec []Block) (string, error) {
	if len(spec) == 0 {
		return "", fmt.Errorf("no blocks to derive")
	}
	seed, _ := hex.DecodeString(em.Seed)
	public, _ := hex.DecodeString(em.Round.Randomness)
	base := fmt.Sprintf("%s|%s|%d", em.Version, name, em.DrandRound)

	blocks := make([][]int, 0, len(spec))
	for i, b := range spec {
		s := &stream{seed: seed, public: public, context: []byte(base + "|b" + strconv.Itoa(i))}
		values, err := deriveBlock(s, b)
		if err != nil {
			return "", err
		}
		blocks = append(blocks, values)
	}
	return shape(name, spec, blocks)
}

func deriveBlock(s *stream, b Block) ([]int, error) {
	universe := b.Max - b.Min + 1
	if universe < 1 {
		return nil, fmt.Errorf("empty universe [%d..%d]", b.Min, b.Max)
	}
	count := b.Count
	if count == 0 {
		count = 1
	}

	switch b.Mold {
	case "discrete_uniform":
		return []int{b.Min + s.integer(universe)}, nil

	case "sample_without_replacement":
		if count > universe {
			return nil, fmt.Errorf("asks for %d out of %d", count, universe)
		}
		out := sampleWithoutReplacement(s, universe, count, b.Min)
		sort.Ints(out)
		return out, nil

	case "permutation":
		if count > universe {
			return nil, fmt.Errorf("asks for %d out of %d", count, universe)
		}
		return sampleWithoutReplacement(s, universe, count, b.Min), nil

	case "uniform_vector_with_replacement", "random_matrix":
		out := make([]int, count)
		for i := range out {
			out[i] = b.Min + s.integer(universe)
		}
		return out, nil

	// min and max already carry the scale, so the span is read straight off
	// the file. Multiplying again is the classic reimplementation bug.
	case "truncated_continuous":
		return []int{b.Min + s.integer(b.Max-b.Min+1)}, nil
	}
	return nil, fmt.Errorf("unknown mold %q", b.Mold)
}

// shape renders the result the way the file publishes it. The shape depends on
// the mold: a scalar, a list, a list of rows, or one list per block.
func shape(name string, blocks []Block, values [][]int) (string, error) {
	if len(blocks) > 1 {
		return jsonOf(values)
	}
	flat := values[0]

	switch blocks[0].Mold {
	case "discrete_uniform", "truncated_continuous":
		return jsonOf(flat[0])

	case "random_matrix":
		rows, cols := dimensions(name, len(flat))
		out := make([][]int, 0, rows)
		for i := 0; i < rows; i++ {
			out = append(out, flat[i*cols:(i+1)*cols])
		}
		return jsonOf(out)
	}
	return jsonOf(flat)
}

// dimensions reads the matrix shape from the variant name, m-<rows>x<cols>.
func dimensions(name string, total int) (int, int) {
	var rows, cols int
	if n, _ := fmt.Sscanf(name, "m-%dx%d", &rows, &cols); n == 2 &&
		rows > 0 && cols > 0 && rows*cols == total {
		return rows, cols
	}
	return 1, total
}

// --- The byte stream -------------------------------------------------------

type stream struct {
	seed, public, context []byte
	buf                   []byte
	pos                   int
}

func (s *stream) nextByte() byte {
	if s.pos >= len(s.buf) {
		info := append(append([]byte{}, s.context...), '|')
		info = append(info, []byte(strconv.Itoa(len(s.buf)))...)
		s.buf = append(s.buf, hkdf(s.seed, s.public, info, HKDF_BLOCK)...)
	}
	b := s.buf[s.pos]
	s.pos++
	return b
}

// integer returns a uniform value in [0,limit) with no modulo bias: values
// above the last whole multiple of limit are discarded and drawn again.
func (s *stream) integer(limit int) int {
	if limit <= 1 {
		return 0
	}
	width, space := 1, 256
	for space < limit {
		width++
		space *= 256
	}
	cut := (space / limit) * limit

	for {
		v := 0
		for i := 0; i < width; i++ {
			v = v*256 + int(s.nextByte())
		}
		if v < cut {
			return v % limit
		}
	}
}

// hkdf is HKDF-SHA256, RFC 5869, both stages.
func hkdf(ikm, salt, info []byte, length int) []byte {
	extract := hmac.New(sha256.New, salt)
	extract.Write(ikm)
	prk := extract.Sum(nil)

	out := make([]byte, 0, length)
	block := []byte{}
	for i := byte(1); len(out) < length; i++ {
		expand := hmac.New(sha256.New, prk)
		expand.Write(block)
		expand.Write(info)
		expand.Write([]byte{i})
		block = expand.Sum(nil)
		out = append(out, block...)
	}
	return out[:length]
}

// sampleWithoutReplacement draws k distinct values in the order they come out,
// with a partial Fisher-Yates over a sparse map.
func sampleWithoutReplacement(s *stream, universe, count, min int) []int {
	moved := make(map[int]int, count)
	out := make([]int, 0, count)

	for i := 0; i < count; i++ {
		j := i + s.integer(universe-i)

		vj, ok := moved[j]
		if !ok {
			vj = j
		}
		vi, ok := moved[i]
		if !ok {
			vi = i
		}
		moved[j], moved[i] = vi, vj
		out = append(out, min+vj)
	}
	return out
}

// --- Plumbing --------------------------------------------------------------

func splitJWS(raw string) (header, payload, signature []byte, err error) {
	parts := strings.Split(strings.TrimSpace(raw), ".")
	if len(parts) != 3 {
		return nil, nil, nil, fmt.Errorf("expected 3 dot-separated parts, got %d", len(parts))
	}
	if header, err = b64(parts[0]); err != nil {
		return nil, nil, nil, err
	}
	if payload, err = b64(parts[1]); err != nil {
		return nil, nil, nil, err
	}
	signature, err = b64(parts[2])
	return header, payload, signature, err
}

func b64(s string) ([]byte, error) { return base64.RawURLEncoding.DecodeString(s) }

// publicKey takes the key from the command line. The kid in the header says
// WHICH key signed; resolving it against the published registry is the caller's
// job, and skipping that check is what "UNVERIFIABLE" means.
func publicKey(header []byte) ed25519.PublicKey {
	var h struct {
		Kid string `json:"kid"`
	}
	_ = json.Unmarshal(header, &h)
	fmt.Println("key id    :", h.Kid)

	if len(os.Args) < 3 {
		return nil
	}
	key, err := hex.DecodeString(strings.TrimSpace(os.Args[2]))
	if err != nil || len(key) != ed25519.PublicKeySize {
		unverifiable("the public key must be %d hex-encoded bytes", ed25519.PublicKeySize)
	}
	return key
}

func read(source string) (string, error) {
	if strings.HasPrefix(source, "http://") || strings.HasPrefix(source, "https://") {
		return get(source)
	}
	b, err := os.ReadFile(source)
	return string(b), err
}

func get(u string) (string, error) {
	client := &http.Client{Timeout: HTTP_TIMEOUT}
	resp, err := client.Get(u)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HTTP %s", resp.Status)
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	return string(b), err
}

func drandRandomness(round uint64) (string, error) {
	body, err := get(fmt.Sprintf("%s/public/%d", DRAND_RELAY, round))
	if err != nil {
		return "", err
	}
	var r struct {
		Randomness string `json:"randomness"`
	}
	if err := json.Unmarshal([]byte(body), &r); err != nil {
		return "", err
	}
	return r.Randomness, nil
}

func jsonOf(v any) (string, error) {
	b, err := json.Marshal(v)
	return string(b), err
}

func notVerified(format string, a ...any) {
	fmt.Println()
	fmt.Printf("NOT VERIFIED: "+format+"\n", a...)
	os.Exit(1)
}

func unverifiable(format string, a ...any) {
	fmt.Println()
	fmt.Printf("UNVERIFIABLE: "+format+"\n", a...)
	os.Exit(3)
}
