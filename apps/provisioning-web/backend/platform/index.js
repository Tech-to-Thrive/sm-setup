/**
 * Platform factory - creates the appropriate platform handler
 */

const LinuxPlatform = require('./linux');
const WindowsPlatform = require('./windows');
const DarwinPlatform = require('./darwin');
const PlatformBase = require('./base');

class PlatformFactory {
    static create(platform = process.platform) {
        switch (platform) {
            case 'linux':
                return new LinuxPlatform();
            
            case 'win32':
                return new WindowsPlatform();
            
            case 'darwin':
                return new DarwinPlatform();
            
            default:
                console.warn(`Unknown platform: ${platform}, using base implementation`);
                return new PlatformBase();
        }
    }

    static getPlatform() {
        if (!this._instance) {
            this._instance = this.create();
        }
        return this._instance;
    }
}

// Export both the factory and a singleton instance
module.exports = {
    PlatformFactory,
    platform: PlatformFactory.getPlatform()
};