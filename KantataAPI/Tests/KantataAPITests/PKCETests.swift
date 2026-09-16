import Testing
@testable import KantataAPI

@Suite("PKCE")
struct PKCETests {
    @Test("code verifier is 43-128 chars from the unreserved character set")
    func verifierFormat() {
        let pkce = PKCE()
        #expect(pkce.codeVerifier.count >= 43 && pkce.codeVerifier.count <= 128)
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(pkce.codeVerifier.allSatisfy { allowed.contains($0) })
    }

    @Test("code challenge is base64url with no padding")
    func challengeFormat() {
        let pkce = PKCE()
        #expect(!pkce.codeChallenge.contains("+"))
        #expect(!pkce.codeChallenge.contains("/"))
        #expect(!pkce.codeChallenge.contains("="))
    }

    @Test("challenge method is S256")
    func challengeMethod() {
        #expect(PKCE().codeChallengeMethod == "S256")
    }

    @Test("two instances produce different verifiers")
    func randomness() {
        #expect(PKCE().codeVerifier != PKCE().codeVerifier)
    }

    @Test("matches the known RFC 7636 Appendix B test vector")
    func rfc7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        #expect(PKCE.challenge(forVerifier: verifier) == expectedChallenge)
    }
}
