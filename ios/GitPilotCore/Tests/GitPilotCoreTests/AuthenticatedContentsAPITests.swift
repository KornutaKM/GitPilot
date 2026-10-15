import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import GitPilotCore

final class AuthenticatedContentsAPITests: XCTestCase {
    private var repository: PublicRepository {
        try! JSONDecoder().decode(PublicRepository.self, from: Data("""
        {"id":99,"name":"secret","full_name":"Octocat/secret","description":null,
         "default_branch":"main","language":"Swift","stargazers_count":0,
         "html_url":"https://github.com/Octocat/secret","private":true}
        """.utf8))
    }
    private var file: PublicFileEntry {
        try! JSONDecoder().decode(PublicFileEntry.self, from: Data("""
        {"name":"README.md","path":"README.md","type":"file","size":6,"html_url":null}
        """.utf8))
    }
    private func client(status: Int = 200, body: String,
                        redirected: URL? = nil,
                        check: @escaping (URLRequest) -> Void = { _ in }
    ) -> AuthenticatedContentsAPI {
        AuthenticatedContentsAPI { request in
            check(request)
            return (Data(body.utf8),
                    HTTPURLResponse(url: redirected ?? request.url!, statusCode: status,
                                    httpVersion: nil, headerFields: nil)!)
        }
    }

    func testOnlyAuthenticatedGETCanListAProtectedDirectory() async throws {
        let payload = """
        [{"name":"README.md","path":"README.md","type":"file","size":6,"html_url":null},
         {"name":"Sources","path":"Sources","type":"dir","size":0,"html_url":null}]
        """
        let api = client(body: payload) { req in
            XCTAssertEqual(req.httpMethod, "GET")
            XCTAssertEqual(req.url?.host, "api.github.com")
            XCTAssertEqual(req.url?.path, "/repos/Octocat/secret/contents")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer private-fixture")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertEqual(URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "ref" })?.value, "main")
        }
        let list = try await api.directory(repository: repository, branch: "main", token: "private-fixture")
        XCTAssertEqual(list.map(\.name), ["Sources", "README.md"])
    }

    func testSmallPrivateTextIsDecodedInMemoryWithStrictByteCount() async throws {
        let api = client(body: """
        {"type":"file","path":"README.md","size":6,"encoding":"base64",
         "content":"aGVsbG8K","html_url":"https://github.com/Octocat/secret/blob/main/README.md"}
        """)
        let contents = try await api.preview(repository: repository, branch: "main",
                                             file: file, token: "private-fixture")
        XCTAssertEqual(contents.text, "hello\n")
        XCTAssertEqual(contents.path, "README.md")
    }

    func testMalformedPathAndCredentialsNeverMakeNetworkRequests() async {
        let api = client(body: "[]") { _ in XCTFail("Unsafe input reached network") }
        let invalidPaths = ["../private", "/private", "a//b", "a/../b",
                            "file?token=x", "file#part", "file%0A", "bad\\path", "a\nInjected"]
        for path in invalidPaths {
            XCTAssertFalse(AuthenticatedContentsAPI.validPath(path))
            do {
                _ = try await api.directory(repository: repository, branch: "main",
                                            path: path, token: "test")
                XCTFail("Unsafe path accepted")
            } catch { XCTAssertEqual(error as? AuthenticatedContentsAPI.ReadError, .invalidInput) }
        }
        do {
            _ = try await api.directory(repository: repository, branch: "main", token: "bad\r\nheader")
            XCTFail("Token header injection accepted")
        } catch { XCTAssertEqual(error as? AuthenticatedContentsAPI.ReadError, .invalidInput) }
    }

    func testGitHubResponseRedirectCannotCarryBearer() async {
        let api = client(body: "[]", redirected: URL(string: "https://evil.test/steal")!)
        do {
            _ = try await api.directory(repository: repository, branch: "main", token: "private-fixture")
            XCTFail("Redirect accepted")
        } catch { XCTAssertEqual(error as? AuthenticatedContentsAPI.ReadError, .untrustedResponse) }
    }

    func testRevokedAndForbiddenMustBeReportedDistinctly() async {
        for (status, code) in [(401, AuthenticatedContentsAPI.ReadError.revoked),
                               (403, .forbidden), (500, .unavailable)] {
            let api = client(status: status, body: "[]")
            do {
                _ = try await api.directory(repository: repository, branch: "main", token: "private-fixture")
                XCTFail("Non-200 returned success")
            } catch { XCTAssertEqual(error as? AuthenticatedContentsAPI.ReadError, code) }
        }
    }

    func testInvalidAndBinaryPrivateFileNeverProducePreview() async {
        let payloads = [
            #"{"type":"file","path":"README.md","size":6,"encoding":"base64","content":"!!!!"}"#,
            #"{"type":"file","path":"README.md","size":2,"encoding":"base64","content":"AAE="}"#,
            #"{"type":"file","path":"wrong.md","size":6,"encoding":"base64","content":"aGVsbG8K"}"#,
            #"{"type":"file","path":"README.md","size":70000,"encoding":"base64","content":"aGVsbG8K"}"#,
            #"{"type":"symlink","path":"README.md","size":6,"encoding":"base64","content":"aGVsbG8K"}"#
        ]
        for payload in payloads {
            let api = client(body: payload)
            do {
                _ = try await api.preview(repository: repository, branch: "main", file: file,
                                          token: "private-fixture")
                XCTFail("Unsafe preview accepted")
            } catch { XCTAssertEqual(error as? AuthenticatedContentsAPI.ReadError, .invalidPayload) }
        }
    }

    func testDirectoryListCapAndNestedTraversalCheck() async {
        let item = #"{"name":"README.md","path":"README.md","type":"file","size":6,"html_url":null}"#
        let excessive = "[" + Array(repeating: item, count: 101).joined(separator: ",") + "]"
        let api = client(body: excessive)
        do { _ = try await api.directory(repository: repository, branch: "main", token: "private-fixture")
            XCTFail("Unbounded page accepted") }
        catch { XCTAssertEqual(error as? AuthenticatedContentsAPI.ReadError, .invalidPayload) }
        let foreign = client(body: """
        [{"name":"steal","path":"other/steal","type":"file","size":1}]
        """)
        do {
            _ = try await foreign.directory(repository: repository, branch: "main",
                                             path: "nested", token: "private-fixture")
            XCTFail("Out-of-directory response accepted")
        } catch { XCTAssertEqual(error as? AuthenticatedContentsAPI.ReadError, .invalidPayload) }
    }

    func testOversizedBodyCannotBeDecodedOrStored() async {
        let api = client(body: String(repeating: "a", count: 1_200_001))
        do {
            _ = try await api.directory(repository: repository, branch: "main",
                                        token: "private-fixture")
            XCTFail("Oversized protected directory accepted")
        } catch { XCTAssertEqual(error as? AuthenticatedContentsAPI.ReadError, .oversizedResponse) }
    }

    func testMalformedBranchOrOversizedFileFailsBeforeDownload() async {
        let api = client(body: "[]") { _ in XCTFail("Unsafe ref reached GitHub") }
        do {
            _ = try await api.directory(repository: repository,
                                        branch: "main\\nAuthorization", token: "private-fixture")
            XCTFail("Unsafe branch accepted")
        } catch { XCTAssertEqual(error as? AuthenticatedContentsAPI.ReadError, .invalidInput) }
        let oversized = try! JSONDecoder().decode(PublicFileEntry.self, from: Data("""
        {"name":"large.txt","path":"large.txt","type":"file","size":64001}
        """.utf8))
        do {
            _ = try await api.preview(repository: repository, branch: "main",
                                      file: oversized, token: "private-fixture")
            XCTFail("Oversized file preview accepted")
        } catch { XCTAssertEqual(error as? AuthenticatedContentsAPI.ReadError, .oversizedResponse) }
    }
}
