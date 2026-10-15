import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import GitPilotCore

final class PublicRepositoryBrowserTests: XCTestCase {
    private var repo: PublicRepository {
        try! JSONDecoder().decode(PublicRepository.self, from: Data("""
        {"id":42,"name":"GitPilot","full_name":"Octocat/GitPilot","description":null,
        "default_branch":"main","language":"Swift","stargazers_count":0,
        "html_url":"https://github.com/Octocat/GitPilot","private":false}
        """.utf8))
    }

    private func mock(_ answer: @escaping (URLRequest) throws -> String) -> PublicGitHubAPI {
        PublicGitHubAPI { request in
            let data = Data(try answer(request).utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200,
                                          httpVersion: nil, headerFields: nil)!)
        }
    }

    func testRefAndPathValidationRejectTraversal() {
        XCTAssertTrue(PublicGitHubAPI.validBranchRef("feature/ios-v2"))
        XCTAssertFalse(PublicGitHubAPI.validBranchRef("../main"))
        XCTAssertFalse(PublicGitHubAPI.validBranchRef("refs//heads/main"))
        XCTAssertFalse(PublicGitHubAPI.validBranchRef("main\nAuthorization:secret"))
        XCTAssertTrue(PublicGitHubAPI.validRepositoryPath("Sources/File.swift"))
        for path in ["../secret", "Sources/../secret", "/tmp", "bad//path",
                     "bad\\path", String(repeating: "a", count: 1025)] {
            XCTAssertFalse(PublicGitHubAPI.validRepositoryPath(path))
        }
    }

    func testDirectorySortsFoldersAndRejectsUnauthenticatedWrites() async throws {
        let client = mock { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.url?.path, "/repos/Octocat/GitPilot/contents")
            XCTAssertTrue(request.url!.absoluteString.contains("ref=main"))
            return """
            [
              {"name":"Z.swift","path":"Z.swift","type":"file","size":6,"html_url":null},
              {"name":"Sources","path":"Sources","type":"dir","size":0,"html_url":null},
              {"name":"A.swift","path":"A.swift","type":"file","size":6,"html_url":null}
            ]
            """
        }
        let files = try await client.directory(repository: repo, branch: "main")
        XCTAssertEqual(files.map(\.name), ["Sources","A.swift","Z.swift"])
    }

    func testUTF8PreviewIsSizeBoundedAndStrict() async throws {
        let file = PublicFileEntryFixture.file()
        let client = mock { request in
            XCTAssertEqual(request.url?.path, "/repos/Octocat/GitPilot/contents/README.md")
            return """
            {"type":"file","path":"README.md","size":6,
             "encoding":"base64","content":"aGVsbG8K",
             "html_url":"https://github.com/Octocat/GitPilot/blob/main/README.md"}
            """
        }
        let preview = try await client.preview(repository: repo, branch: "main", file: file)
        XCTAssertEqual(preview.text, "hello\n")
        XCTAssertEqual(preview.path, "README.md")
    }

    func testPreviewRejectsBinaryAndInvalidBase64() async {
        let file = PublicFileEntryFixture.file()
        let invalid = [
            #"{"type":"file","path":"README.md","size":6,"encoding":"base64","content":"!!"}"#,
            #"{"type":"file","path":"README.md","size":2,"encoding":"base64","content":"AAE="}"#,
            #"{"type":"file","path":"README.md","size":9,"encoding":"base64","content":"aGVsbG8K"}"#
        ]
        for body in invalid {
            let client = mock { _ in body }
            do {
                _ = try await client.preview(repository: repo, branch: "main", file: file)
                XCTFail("Expected strict preview rejection")
            } catch { XCTAssertEqual(error as? PublicGitHubError, .invalidResponse) }
        }
    }

    func testRecentCommitsAreBoundedAndDecoded() async throws {
        let client = mock { request in
            XCTAssertEqual(request.url?.path, "/repos/Octocat/GitPilot/commits")
            XCTAssertTrue(request.url!.absoluteString.contains("per_page=12"))
            return """
            [{"sha":"abcdef0123456789","commit":{"message":"Update docs\\nmore detail"},
              "html_url":"https://github.com/Octocat/GitPilot/commit/abcdef0123456789"}]
            """
        }
        let commits = try await client.recentCommits(repository: repo, branch: "main")
        XCTAssertEqual(commits.first?.subject, "Update docs")
        XCTAssertEqual(commits.count, 1)
    }
}

private enum PublicFileEntryFixture {
    static func file() -> PublicFileEntry {
        try! JSONDecoder().decode(PublicFileEntry.self, from: Data("""
        {"name":"README.md","path":"README.md","type":"file","size":6,"html_url":null}
        """.utf8))
    }
}
