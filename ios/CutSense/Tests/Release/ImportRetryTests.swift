import XCTest
@testable import CutSense

final class ImportRetryTests: XCTestCase {
    func testPhotosExportFailuresAreRetried() {
        let export = NSError(domain: "PHAssetExportRequestErrorDomain", code: 3)
        let helper = NSError(domain: NSCocoaErrorDomain, code: 4101, userInfo: [NSUnderlyingErrorKey: export])
        let provider = NSError(domain: NSItemProvider.errorDomain, code: -1000, userInfo: [NSUnderlyingErrorKey: helper])
        XCTAssertTrue(VideoImportService.isTransientExportFailure(provider))
        XCTAssertTrue(VideoImportService.isTransientExportFailure(helper))
        XCTAssertTrue(VideoImportService.isTransientExportFailure(NSError(domain: "CoreTransferable.TransferableSupportError", code: 0)))
    }

    func testOtherFailuresAreNot() {
        XCTAssertFalse(VideoImportService.isTransientExportFailure(CancellationError()))
        XCTAssertFalse(VideoImportService.isTransientExportFailure(NSError(domain: NSCocoaErrorDomain, code: 640))) // out of space
        XCTAssertFalse(VideoImportService.isTransientExportFailure(VideoImportService.ImportError.missingAudio))
    }
}
