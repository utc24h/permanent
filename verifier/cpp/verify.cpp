// Reference verifier for the randomness beacon.
//
//     g++ -std=c++17 -O2 verify.cpp -lcrypto -o verify
//     ./verify emission.jws [public-key-hex]
//
// Two dependencies, both packaged everywhere:
//
//     OpenSSL (libcrypto)   SHA-256, HMAC and Ed25519
//                           https://openssl-library.org
//                           apt install libssl-dev
//
//     nlohmann/json         header only
//                           https://github.com/nlohmann/json
//                           apt install nlohmann-json3-dev
//
// It reads a file, not a URL:
//     curl -s https://.../1730-emission.jws -o e.jws && ./verify e.jws
//
// It does not check drand's BLS signature: that needs a pairing library. Ask
// drand for the round instead — the round travels whole inside the file.

#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/sha.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <map>
#include <nlohmann/json.hpp>
#include <sstream>
#include <string>
#include <vector>

using json = nlohmann::json;
using Bytes = std::vector<uint8_t>;

namespace {

constexpr int HKDF_BLOCK = 64;

// --- Encoding --------------------------------------------------------------

Bytes fromHex(const std::string& hex) {
    Bytes out(hex.size() / 2);
    for (size_t i = 0; i < out.size(); i++)
        out[i] = (uint8_t)std::stoul(hex.substr(i * 2, 2), nullptr, 16);
    return out;
}

std::string toHex(const Bytes& b) {
    static const char* D = "0123456789abcdef";
    std::string out;
    for (uint8_t x : b) {
        out += D[x >> 4];
        out += D[x & 15];
    }
    return out;
}

Bytes fromB64Url(std::string s) {
    for (char& c : s)
        if (c == '-') c = '+';
        else if (c == '_') c = '/';
    size_t pad = (4 - s.size() % 4) % 4;
    s.append(pad, '=');

    Bytes out(s.size());
    int n = EVP_DecodeBlock((unsigned char*)out.data(), (const unsigned char*)s.data(),
                            (int)s.size());
    if (n < 0) return {};
    out.resize(n - pad);
    return out;
}

// --- Crypto ----------------------------------------------------------------

Bytes sha256(const Bytes& data) {
    Bytes out(SHA256_DIGEST_LENGTH);
    SHA256(data.data(), data.size(), out.data());
    return out;
}

// HKDF-SHA256, RFC 5869, both stages.
Bytes hkdf(const Bytes& ikm, const Bytes& salt, const Bytes& info, size_t length) {
    unsigned int len = 0;
    Bytes prk(EVP_MAX_MD_SIZE);
    HMAC(EVP_sha256(), salt.data(), (int)salt.size(), ikm.data(), ikm.size(), prk.data(), &len);
    prk.resize(len);

    Bytes out, block;
    for (uint8_t i = 1; out.size() < length; i++) {
        Bytes in = block;
        in.insert(in.end(), info.begin(), info.end());
        in.push_back(i);

        block.assign(EVP_MAX_MD_SIZE, 0);
        HMAC(EVP_sha256(), prk.data(), (int)prk.size(), in.data(), in.size(), block.data(), &len);
        block.resize(len);
        out.insert(out.end(), block.begin(), block.end());
    }
    out.resize(length);
    return out;
}

bool verifyEd25519(const Bytes& key, const Bytes& msg, const Bytes& sig) {
    EVP_PKEY* pkey = EVP_PKEY_new_raw_public_key(EVP_PKEY_ED25519, nullptr, key.data(), key.size());
    if (!pkey) return false;

    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    bool ok = EVP_DigestVerifyInit(ctx, nullptr, nullptr, nullptr, pkey) == 1 &&
              EVP_DigestVerify(ctx, sig.data(), sig.size(), msg.data(), msg.size()) == 1;
    EVP_MD_CTX_free(ctx);
    EVP_PKEY_free(pkey);
    return ok;
}

// --- The byte stream -------------------------------------------------------

struct Stream {
    Bytes seed, pub, context, buf;
    size_t pos = 0;

    uint8_t nextByte() {
        if (pos >= buf.size()) {
            Bytes info = context;
            info.push_back('|');
            std::string n = std::to_string(buf.size());
            info.insert(info.end(), n.begin(), n.end());

            Bytes block = hkdf(seed, pub, info, HKDF_BLOCK);
            buf.insert(buf.end(), block.begin(), block.end());
        }
        return buf[pos++];
    }

    // Uniform value in [0,limit) with no modulo bias: values above the last
    // whole multiple of limit are discarded and drawn again.
    long integer(long limit) {
        if (limit <= 1) return 0;

        int width = 1;
        long space = 256;
        while (space < limit) {
            width++;
            space *= 256;
        }
        long cut = (space / limit) * limit;

        for (;;) {
            long v = 0;
            for (int i = 0; i < width; i++) v = v * 256 + nextByte();
            if (v < cut) return v % limit;
        }
    }
};

// --- Derivation ------------------------------------------------------------

struct Block {
    std::string mold;
    long count = 1, min = 0, max = 0;
};

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
std::vector<Block> blocksOf(const std::string& group, const json& v) {
    std::vector<Block> out;

    if (group == "composite") {
        for (const auto& b : v.at("blocks"))
            out.push_back({b.at("mold").get<std::string>(), b.value("count", 1L),
                           b.at("min").get<long>(), b.at("max").get<long>()});
        return out;
    }

    long count = group == "random_matrix" ? v.at("rows").get<long>() * v.at("cols").get<long>()
                                          : v.value("count", 1L);
    out.push_back({group, count, v.at("min").get<long>(), v.at("max").get<long>()});
    return out;
}

// Draws k distinct values in the order they come out, with a partial
// Fisher-Yates over a sparse map.
std::vector<long> sampleWithoutReplacement(Stream& s, long universe, long count, long min) {
    std::map<long, long> moved;
    std::vector<long> out;

    for (long i = 0; i < count; i++) {
        long j = i + s.integer(universe - i);
        long vj = moved.count(j) ? moved[j] : j;
        long vi = moved.count(i) ? moved[i] : i;
        moved[j] = vi;
        moved[i] = vj;
        out.push_back(min + vj);
    }
    return out;
}

std::vector<long> deriveBlock(Stream& s, const Block& b) {
    long universe = b.max - b.min + 1;
    long count = b.count ? b.count : 1;

    if (b.mold == "discrete_uniform") return {b.min + s.integer(universe)};

    if (b.mold == "sample_without_replacement") {
        auto out = sampleWithoutReplacement(s, universe, count, b.min);
        std::sort(out.begin(), out.end());
        return out;
    }

    if (b.mold == "permutation") return sampleWithoutReplacement(s, universe, count, b.min);

    if (b.mold == "uniform_vector_with_replacement" || b.mold == "random_matrix") {
        std::vector<long> out;
        for (long i = 0; i < count; i++) out.push_back(b.min + s.integer(universe));
        return out;
    }

    // min and max already carry the scale, so the span is read straight off the
    // file. Multiplying again is the classic reimplementation bug.
    if (b.mold == "truncated_continuous") return {b.min + s.integer(b.max - b.min + 1)};

    throw std::runtime_error("unknown mold " + b.mold);
}

// Renders the result the way the file publishes it: a scalar, a list, a list of
// rows, or one list per block.
json shape(const std::string& name, const std::vector<Block>& spec,
           const std::vector<std::vector<long>>& values) {
    if (spec.size() > 1) return values;

    const auto& flat = values[0];
    const std::string& mold = spec[0].mold;

    if (mold == "discrete_uniform" || mold == "truncated_continuous") return flat[0];

    if (mold == "random_matrix") {
        long rows = 1, cols = (long)flat.size();
        if (sscanf(name.c_str(), "m-%ldx%ld", &rows, &cols) != 2 ||
            rows * cols != (long)flat.size()) {
            rows = 1;
            cols = (long)flat.size();
        }
        std::vector<std::vector<long>> out;
        for (long r = 0; r < rows; r++)
            out.push_back({flat.begin() + r * cols, flat.begin() + (r + 1) * cols});
        return out;
    }
    return flat;
}

[[noreturn]] void notVerified(const std::string& why) {
    std::cout << "\nNOT VERIFIED: " << why << "\n";
    exit(1);
}

[[noreturn]] void unverifiable(const std::string& why) {
    std::cout << "\nUNVERIFIABLE: " << why << "\n";
    exit(3);
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cout << "usage: verify <file.jws> [public-key-hex]\n";
        return 2;
    }

    std::ifstream in(argv[1]);
    if (!in) unverifiable(std::string("cannot read ") + argv[1]);
    std::stringstream ss;
    ss << in.rdbuf();
    std::string raw = ss.str();
    while (!raw.empty() && isspace((unsigned char)raw.back())) raw.pop_back();

    size_t d1 = raw.find('.'), d2 = raw.rfind('.');
    if (d1 == std::string::npos || d1 == d2) notVerified("expected 3 dot-separated parts");

    Bytes headerRaw = fromB64Url(raw.substr(0, d1));
    Bytes payloadRaw = fromB64Url(raw.substr(d1 + 1, d2 - d1 - 1));

    json header = json::parse(std::string(headerRaw.begin(), headerRaw.end()));
    json em = json::parse(std::string(payloadRaw.begin(), payloadRaw.end()));

    std::string version = em.at("version");
    long round = em.at("drand_round");

    std::cout << "file      : " << em.value("type", "?") << " turn " << em.value("utc_turn", "?")
              << ", version " << version << ", drand round " << round << "\n";
    std::cout << "key id    : " << header.value("kid", "?") << "\n";

    // 1. Signature, over the RAW text: re-serializing the JSON changes the
    // bytes and breaks a signature that is perfectly valid.
    if (argc > 2) {
        std::string signedPart = raw.substr(0, d2);
        Bytes msg(signedPart.begin(), signedPart.end());
        if (!verifyEd25519(fromHex(argv[2]), msg, fromB64Url(raw.substr(d2 + 1))))
            notVerified("the Ed25519 signature does not verify");
        std::cout << "signature : OK\n";
    } else {
        std::cout << "signature : SKIPPED, no public key given\n";
    }

    // 2. The revealed seed must hash to what was committed.
    Bytes seed = fromHex(em.at("seed").get<std::string>());
    if (toHex(sha256(seed)) != em.at("seed_sha256").get<std::string>())
        notVerified("SHA-256 of the seed does not match seed_sha256");
    std::cout << "seed      : OK, matches its own hash\n";

    Bytes pub = fromHex(em.at("round").at("randomness").get<std::string>());

    // 3. Every number, reproduced from the seed and the round.
    int checked = 0, failed = 0;
    for (const auto& group : em.at("variants").items()) {
        for (const auto& variant : group.value().items()) {
            const std::string& name = variant.key();
            std::vector<Block> spec = blocksOf(group.key(), variant.value());

            std::vector<std::vector<long>> blocks;
            for (size_t i = 0; i < spec.size(); i++) {
                std::string ctx =
                    version + "|" + name + "|" + std::to_string(round) + "|b" + std::to_string(i);
                Stream s{seed, pub, Bytes(ctx.begin(), ctx.end())};
                blocks.push_back(deriveBlock(s, spec[i]));
            }

            json got = shape(name, spec, blocks);
            const json& want = variant.value().at("result");
            if (got != want) {
                failed++;
                std::cout << "  " << name << " MISMATCH\n     expected " << want.dump()
                          << "\n     computed " << got.dump() << "\n";
                continue;
            }
            checked++;
        }
    }
    if (failed) notVerified(std::to_string(failed) + " variants do not reproduce");
    std::cout << "numbers   : OK, " << checked << " variants reproduced\n";

    std::cout << "\nVERIFIED\n";
    return 0;
}
