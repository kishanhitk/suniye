import XCTest
@testable import Suniye

final class AudioDeviceTransportTests: XCTestCase {
    func testBluetoothClassification() {
        XCTAssertTrue(AudioDeviceTransport.bluetooth.isBluetooth)
        XCTAssertTrue(AudioDeviceTransport.bluetoothLE.isBluetooth)
        XCTAssertFalse(AudioDeviceTransport.builtIn.isBluetooth)
        XCTAssertFalse(AudioDeviceTransport.usb.isBluetooth)
    }

    func testRecommendedPhysicalInputs() {
        XCTAssertTrue(AudioDeviceTransport.builtIn.isRecommendedPhysicalInput)
        XCTAssertTrue(AudioDeviceTransport.usb.isRecommendedPhysicalInput)
        XCTAssertFalse(AudioDeviceTransport.bluetooth.isRecommendedPhysicalInput)
        XCTAssertFalse(AudioDeviceTransport.virtual.isRecommendedPhysicalInput)
    }
}
