#!/usr/bin/env node

//===================================================================
// Volumio Network Manager
// Original Copyright: Michelangelo Guarise - Volumio.org
// Maintainer: Just a Nerd
// Volumio Wireless Daemon - Version 4.0-rc5
// Maintainer: Development Team
// 
// RELEASE CANDIDATE 5 - Hotspot Startup Race Fix
// 
// Major Changes in v4.0:
// - Single Network Mode (SNM) with ethernet/WiFi coordination
// - Emergency hotspot fallback when no network available
// - Improved transition handling and state management
// - Fixed deadlock and infinite loop issues
// - Enhanced logging and diagnostics
//
// RC5 Changes (Hotspot Startup Race Fix):
// - Wait for hostapd to initialize before checking is-active status
// - Fixes race where status check ran before hostapd finished starting
// - Prevents unnecessary retry loop killing working hotspot
//
// RC4 Changes (First Boot Hotspot Fix):
// - Use verified hotspot start on first boot (startHotspotFallbackSafe)
// - Fixes hotspot not appearing on fresh install without ethernet
// - Plain startHotspot() did not verify hostapd actually started
//
// RC3 Changes (DHCP Reconnection Fix):
// - Release DHCP lease before ethernet transition (prevents stale lease)
// - Force fresh DHCP request on WiFi reconnect (prevents rebind timeout)
// - Eliminates 50-second DHCP timeout after ethernet unplug
// - Fixes WiFi reconnection failure causing hotspot fallback
// - Fixed regdomain log output showing on two lines (cosmetic)
//
// Production release: v4.0-rc5
//===================================================================

// ===================================================================
// CONFIGURATION CONSTANTS
// ===================================================================
// Debug flag - set via DEBUG_WIRELESS=true in /volumio/.env
var debug = false;
var settleTime = 3000;
var totalSecondsForConnection = 30;
var pollingTime = 1;
var hostapdExitDelay = 500; // Delay after hostapd exits before IP notification (ms)

// ===================================================================
// TIMEOUT CONSTANTS - Single source of truth for all timeout values
// ===================================================================
var EXEC_TIMEOUT_SHORT = 2000;      // General command execution (2s)
var EXEC_TIMEOUT_MEDIUM = 3000;     // Medium operations like regdomain detection (3s)
var EXEC_TIMEOUT_LONG = 5000;       // Long operations like service restarts (5s)
var EXEC_TIMEOUT_SCAN = 10000;      // Network scanning for regdomain (10s)
var KILL_TIMEOUT = 5000;            // kill() timeout wrapper (5s)
var RECONNECT_WAIT = 3000;          // Wait for wpa_supplicant association (3s)
var USB_SETTLE_WAIT = 2000;         // USB WiFi adapter settle time (2s)
var HOTSPOT_RETRY_DELAY = 3000;     // Hotspot fallback retry delay (3s)
var STARTAP_RETRY_DELAY = 2000;     // startAP retry delay (2s)
var HOSTAPD_STARTUP_WAIT = 1000;    // Wait for hostapd to initialize before status check (1s)
var INTERFACE_CHECK_INTERVAL = 500; // Interface ready polling interval (500ms)

// ===================================================================
// COMMAND BINARIES - Single source of truth for all executable paths
// ===================================================================
var SUDO = "/usr/bin/sudo";
var IFCONFIG = "/sbin/ifconfig";
var IW = "/sbin/iw";
var IP = "/sbin/ip";
var DHCPCD = "/sbin/dhcpcd";
var SYSTEMCTL = "/bin/systemctl";
var IWGETID = "/sbin/iwgetid";
var WPA_CLI = "/sbin/wpa_cli";
var WPA_SUPPLICANT = "wpa_supplicant";
var PGREP = "pgrep";
var CAT = "cat";
var GREP = "grep";
var CUT = "cut";
var TR = "tr";

// ===================================================================
// FILE PATHS - Single source of truth for all file system paths
// ===================================================================
// System paths
var VOLUMIO_ENV = "/volumio/.env";
var OS_RELEASE = "/etc/os-release";
var CRDA_CONFIG = "/etc/default/crda";
var WPA_SUPPLICANT_CONF = "/etc/wpa_supplicant/wpa_supplicant.conf";

// Data paths
var DATA_DIR = "/data";
var CONFIG_DIR = DATA_DIR + "/configuration";
var NET_CONFIGURED = CONFIG_DIR + "/netconfigured";
var WLAN_STATIC = CONFIG_DIR + "/wlanstatic";
var NETWORK_CONFIG = CONFIG_DIR + "/system_controller/network/config.json";
var WLAN_STATUS_FILE = DATA_DIR + "/wlan0status";
var ETH_STATUS_FILE = DATA_DIR + "/eth0status";
var SNM_STATUS_FILE = DATA_DIR + "/snm_status";  // Single Network Mode status for backend
var FLAG_DIR = DATA_DIR + "/flagfiles";
var WIRELESS_ESTABLISHED_FLAG = FLAG_DIR + "/wirelessEstablishedOnce";

// Temporary paths
var TMP_DIR = "/tmp";
var WIRELESS_LOG = TMP_DIR + "/wireless.log";
var FORCE_HOTSPOT_FLAG = TMP_DIR + "/forcehotspot";
var NETWORK_STATUS_FILE = TMP_DIR + "/networkstatus";  // Node notifier

// System paths
var SYS_CLASS_NET = "/sys/class/net";
var VOLUMIO_PLUGINS = "/volumio/app/plugins";
var IFCONFIG_LIB = VOLUMIO_PLUGINS + "/system_controller/network/lib/ifconfig.js";

// ===================================================================
// INTERFACE NAMES
// ===================================================================
var wlan = "wlan0";
var eth = "eth0";

// ===================================================================
// COMPOSED COMMANDS - Built from binary paths above
// ===================================================================
var dhclient = SUDO + " " + DHCPCD + " " + wlan;
var justdhclient = DHCPCD + ".*" + wlan;  // Pattern for killing wlan0 dhcpcd only
var wpasupp = WPA_SUPPLICANT + " -s -B -D" + wirelessWPADriver + " -c" + WPA_SUPPLICANT_CONF + " -i" + wlan;
var wpasuppPattern = WPA_SUPPLICANT + ".*" + wlan;  // Pattern for killing wlan0 wpa_supplicant only
var restartdhcpcd = SUDO + " " + SYSTEMCTL + " restart dhcpcd.service";
var starthostapd = SYSTEMCTL + " start hostapd.service";
var stophostapd = SYSTEMCTL + " stop hostapd.service";
var ifconfigHotspot = IFCONFIG + " " + wlan + " 192.168.211.1 up";
var ifconfigWlan = IFCONFIG + " " + wlan + " up";
var ifconfigUp = SUDO + " " + IFCONFIG + " " + wlan + " up";
var ifdeconfig = SUDO + " " + IP + " addr flush dev " + wlan + " && " + SUDO + " " + IFCONFIG + " " + wlan + " down";
var iwgetid = SUDO + " " + IWGETID + " -r";
var wpacli = WPA_CLI + " -i " + wlan;
var iwRegGet = SUDO + " " + IW + " reg get";
var iwScan = SUDO + " " + IW + " " + wlan + " scan";
var iwRegSet = SUDO + " " + IW + " reg set";
var iwList = IW + " list";
var ipLink = IP + " link show " + wlan;
var ipAddr = IP + " addr show " + wlan;
var checkInterfaceLink = "readlink " + SYS_CLASS_NET + "/" + wlan;

// ===================================================================
// NODE MODULES
// ===================================================================
var fs = require('fs-extra')
var thus = require('child_process');
var execSync = require('child_process').execSync;
var exec = require('child_process').exec;
var ifconfig = require(IFCONFIG_LIB);

// ===================================================================
// WIRELESS CONFIGURATION
// ===================================================================
var wirelessWPADriver = getWirelessWPADriverString();
var wpasupp = WPA_SUPPLICANT + " -s -B -D" + wirelessWPADriver + " -c" + WPA_SUPPLICANT_CONF + " -i" + wlan;

// ===================================================================
// WPA STATE MACHINE CONSTANTS (STAGE 2)
// ===================================================================
// WPA supplicant state definitions
var WPA_STATES = {
    DISCONNECTED: 'DISCONNECTED',
    INTERFACE_DISABLED: 'INTERFACE_DISABLED',
    INACTIVE: 'INACTIVE',
    SCANNING: 'SCANNING',
    AUTHENTICATING: 'AUTHENTICATING',
    ASSOCIATING: 'ASSOCIATING',
    FOUR_WAY_HANDSHAKE: '4WAY_HANDSHAKE',
    GROUP_HANDSHAKE: 'GROUP_HANDSHAKE',
    COMPLETED: 'COMPLETED'
};

// State timeout configurations (milliseconds)
var WPA_STATE_TIMEOUTS = {
    SCANNING: 15000,              // 15s to find network
    AUTHENTICATING: 10000,        // 10s to authenticate
    ASSOCIATING: 10000,           // 10s to associate
    FOUR_WAY_HANDSHAKE: 10000,    // 10s for 4-way handshake
    INTERFACE_DISABLED: 5000      // 5s to recover from disabled state
};

// ===================================================================
// STATE VARIABLES
// ===================================================================
var singleNetworkMode = true;  // Default ON for production
var isWiredNetworkActive = false;
var currentEthStatus = 'disconnected';
var usbWifiCapabilities = null;  // Cached USB capabilities
var apStartInProgress = false;
var wirelessFlowInProgress = false;
var retryCount = 0;
var maxRetries = 3;
var wpaerr;
var lesstimer;
var actualTime = 0;
var apstopped = 0;
var stage2Failed = false;  // Stage 2 connection failure flag
var transitionStartTime = 0;  // Track transition timing for diagnostics

// WPA State machine context (Stage 2)
var wpaStateContext = {
    currentState: null,
    previousState: null,
    stateEnterTime: null,
    monitorProcess: null,
    stateCallback: null,
    timeoutHandle: null,
    consecutiveFailures: 0
};

// ===================================================================
// MAIN ENTRY POINT
// ===================================================================
if (process.argv.length < 2) {
    loggerInfo("Volumio Wireless Daemon. Use: start|stop");
} else {
    var args = process.argv[2];
    loggerDebug('WIRELESS DAEMON: ' + args);
    initializeWirelessDaemon();
    switch (args) {
        case "start":
            initializeWirelessFlow();
            break;
        case "stop":
            stopAP(function() {});
            break;
        case "test":
            wstatus("test");
            break;
    }
}

// ===================================================================
// INITIALIZATION FUNCTIONS
// ===================================================================

// Initialize wireless daemon by retrieving environment parameters and starting monitoring
function initializeWirelessDaemon() {
    retrieveEnvParameters();
    startWiredNetworkingMonitor();
    if (debug) {
        var wpasupp = WPA_SUPPLICANT + " -d -s -B -D" + wirelessWPADriver + " -c" + WPA_SUPPLICANT_CONF + " -i" + wlan;
    }
}

// Main initialization entry point
// Detects regulatory domain and starts wireless flow
function initializeWirelessFlow() {
    loggerInfo("Wireless.js initializing wireless flow");
    stop(function() {
        loggerInfo("Cleaning previous...");
        detectAndApplyRegdomain(function() {
            startFlow();
        });
    });
}

// ===================================================================
// PROCESS MANAGEMENT FUNCTIONS
// ===================================================================

// Kill a process by pattern using pkill
// Use pkill to terminate processes matching pattern
// Patterns should be interface-specific (e.g., "dhcpcd.*wlan0", "wpa_supplicant.*wlan0")
function kill(pattern, callback) {
    loggerDebug("kill(): Pattern: " + pattern);
    
    // Use pkill directly to avoid blocking in fs.watch() callback contexts
    var command = 'pkill -f "' + pattern + '"';
    
    // Timeout protection to prevent indefinite blocking
    var callbackFired = false;
    var timeoutHandle = setTimeout(function() {
        if (!callbackFired) {
            callbackFired = true;
            loggerInfo("WARNING: kill() timed out after " + (KILL_TIMEOUT/1000) + "s for: " + pattern);
            callback(new Error('Kill operation timeout'));
        }
    }, KILL_TIMEOUT);
    
    return thus.exec(command, function(err, stdout, stderr) {
        if (!callbackFired) {
            callbackFired = true;
            clearTimeout(timeoutHandle);
            
            // pkill returns 1 if no processes found - NOT an error
            // Since exec() doesn't give us direct access to exit code,
            // we treat ANY pkill error as "not found" (safe assumption)
            // pkill only fails if: no processes (1) or syntax error (2+)
            // Our patterns are static, so syntax errors won't happen in production
            if (err) {
                // Assume "no processes found" which is normal
                loggerDebug("kill(): No processes found: " + pattern);
                return callback(null);
            }
            
            loggerDebug("kill(): Success: " + pattern);
            callback(null);
        }
    });
}

// Extract target process from command string - DEPRECATED
// Process matching now uses interface-specific patterns for reliability
// Keeping function for compatibility but it's not called
function extractTargetProcess(commandString) {
    var parts = commandString.split(" ");
    var firstPart = parts[0];
    
    // Check if command is sudo-wrapped
    if (firstPart === SUDO || firstPart === "/usr/bin/sudo") {
        // Return actual target command (element after sudo)
        if (parts.length > 1) {
            loggerDebug("extractTargetProcess(): Skipping sudo wrapper, target is: " + parts[1]);
            return parts[1];
        }
    }
    
    // Not sudo-wrapped, return first element
    loggerDebug("extractTargetProcess(): Direct command, target is: " + firstPart);
    return firstPart;
}

// Launch a command either synchronously or asynchronously with logging
// sync=true: waits for process to complete before callback
// sync=false: spawns process and calls callback immediately
function launch(fullprocess, name, sync, callback) {
    if (sync) {
        var child = thus.exec(fullprocess, {}, callback);
        child.stdout.on('data', function(data) {
            loggerDebug(name + 'stdout: ' + data);
        });

        child.stderr.on('data', function(data) {
            loggerDebug(name + 'stderr: ' + data);
        });

        child.on('close', function(code) {
            loggerDebug(name + 'child process exited with code ' + code);
        });
    } else {
        var all = fullprocess.split(" ");
        var process = all[0];
        if (all.length > 0) {
            all.splice(0, 1);
        }
        loggerDebug("launching " + process + " args: ");
        loggerDebug(all);
        var child = thus.spawn(process, all, {});
        child.stdout.on('data', function(data) {
            loggerDebug(name + 'stdout: ' + data);
        });

        child.stderr.on('data', function(data) {
            loggerDebug(name + 'stderr: ' + data);
        });

        child.on('close', function(code) {
            loggerDebug(name + 'child process exited with code ' + code);
        });
        callback();
    }

    return
}

// ===================================================================
// HOTSPOT FUNCTIONS
// ===================================================================

// Start WiFi hotspot (Access Point) mode
// If hotspot is disabled in config, only brings interface up without hostapd
function startHotspot(callback) {
    stopHotspot(function(err) {
        if (isHotspotDisabled()) {
            loggerInfo('Hotspot is disabled, not starting it');
            launch(ifconfigWlan, "configwlanup", true, function(err) {
                loggerDebug("ifconfig " + err);
                if (callback) callback();
            });
        } else {
            launch(ifconfigHotspot, "confighotspot", true, function(err) {
                loggerDebug("ifconfig " + err);
                
                // Launch hostapd with custom completion handling
                var all = starthostapd.split(" ");
                var process = all[0];
                if (all.length > 0) {
                    all.splice(0, 1);
                }
                loggerDebug("launching " + process + " args: ");
                loggerDebug(all);
                
                var hostapdChild = thus.spawn(process, all, {});
                
                hostapdChild.stdout.on('data', function(data) {
                    loggerDebug("hotspot stdout: " + data);
                });
                
                hostapdChild.stderr.on('data', function(data) {
                    loggerDebug("hotspot stderr: " + data);
                });
                
                hostapdChild.on('close', function(code) {
                    loggerDebug("hotspotchild process exited with code " + code);
                    
                    // Trigger ip-changed AFTER hostapd actually completes
                    setTimeout(function() {
                        try {
                            execSync(SYSTEMCTL + ' restart ip-changed@' + wlan + '.target', { encoding: 'utf8', timeout: EXEC_TIMEOUT_SHORT });
                            loggerDebug("Triggered ip-changed@" + wlan + ".target for hotspot IP");
                        } catch (e) {
                            loggerDebug("Could not trigger ip-changed target: " + e);
                        }
                    }, hostapdExitDelay);
                });
                
                // Continue with immediate callback for flow control
                updateNetworkState("hotspot");
                if (callback) callback();
            });
        }
    });
}

// Force start hotspot even if disabled (used for factory reset scenarios)
function startHotspotForce(callback) {
    stopHotspot(function(err) {
        launch(ifconfigHotspot, "confighotspot", true, function(err) {
            loggerDebug("ifconfig " + err);
            
            // Launch hostapd with custom completion handling
            var all = starthostapd.split(" ");
            var process = all[0];
            if (all.length > 0) {
                all.splice(0, 1);
            }
            loggerDebug("launching " + process + " args: ");
            loggerDebug(all);
            
            var hostapdChild = thus.spawn(process, all, {});
            
            hostapdChild.stdout.on('data', function(data) {
                loggerDebug("hotspot stdout: " + data);
            });
            
            hostapdChild.stderr.on('data', function(data) {
                loggerDebug("hotspot stderr: " + data);
            });
            
            hostapdChild.on('close', function(code) {
                loggerDebug("hotspotchild process exited with code " + code);
                
                // Trigger ip-changed AFTER forced hostapd actually completes
                setTimeout(function() {
                    try {
                        execSync(SYSTEMCTL + ' restart ip-changed@' + wlan + '.target', { encoding: 'utf8', timeout: EXEC_TIMEOUT_SHORT });
                        loggerDebug("Triggered ip-changed@" + wlan + ".target for forced hotspot IP");
                    } catch (e) {
                        loggerDebug("Could not trigger ip-changed target: " + e);
                    }
                }, hostapdExitDelay);
            });
            
            // Continue with immediate callback for flow control
            // Continue with immediate callback for flow control
            updateNetworkState("hotspot");
            if (callback) callback();
        });
    });
}

// Stop WiFi hotspot and deconfigure interface
function stopHotspot(callback) {
    launch(stophostapd, "stophotspot" , true, function(err) {
        launch(ifdeconfig, "ifdeconfig", true, callback);
    });
}

// Attempt hotspot fallback with retry logic and verification
// Retries up to hotspotMaxRetries times if hotspot fails to start
// Verifies hostapd service is actually active after start
function startHotspotFallbackSafe(retry = 0) {
    const hotspotMaxRetries = 3;

    function handleHotspotResult(err) {
        if (err) {
            loggerInfo(`Hotspot launch failed. Retry ${retry + 1} of ${hotspotMaxRetries}`);
            if (retry + 1 < hotspotMaxRetries) {
                setTimeout(() => startHotspotFallbackSafe(retry + 1), HOTSPOT_RETRY_DELAY);
            } else {
                loggerInfo("Hotspot failed after maximum retries. System remains offline.");
                notifyWirelessReady();
            }
            return;
        }

        // Wait for hostapd to initialize before checking status
        setTimeout(function() {
            // Verify hostapd status
            try {
                const hostapdStatus = execSync(SYSTEMCTL + " is-active hostapd", { encoding: 'utf8' }).trim();
                if (hostapdStatus !== "active") {
                    loggerInfo("Hostapd did not reach active state. Retrying fallback.");
                    if (retry + 1 < hotspotMaxRetries) {
                        setTimeout(() => startHotspotFallbackSafe(retry + 1), HOTSPOT_RETRY_DELAY);
                    } else {
                        loggerInfo("Hostapd failed after maximum retries. System remains offline.");
                        notifyWirelessReady();
                    }
                } else {
                    loggerInfo("Hotspot active and hostapd is running.");
                    updateNetworkState("hotspot");
                    notifyWirelessReady();
                }
            } catch (e) {
                loggerInfo("Error checking hostapd status: " + e.message);
                if (retry + 1 < hotspotMaxRetries) {
                    setTimeout(() => startHotspotFallbackSafe(retry + 1), HOTSPOT_RETRY_DELAY);
                } else {
                    loggerInfo("Could not confirm hostapd status. System remains offline.");
                    notifyWirelessReady();
                }
            }
        }, HOSTAPD_STARTUP_WAIT);
    }

    if (!isWirelessDisabled()) {
        if (checkConcurrentModeSupport()) {
            loggerInfo('Fallback: Concurrent AP+STA supported. Starting hotspot.');
            startHotspot(handleHotspotResult);
        } else {
            loggerInfo('Fallback: Stopping STA and starting hotspot.');
            stopAP(function () {
                setTimeout(() => {
                    startHotspot(handleHotspotResult);
                }, settleTime);
            });
        }
    } else {
        loggerInfo("Fallback: WiFi disabled. No hotspot started.");
        notifyWirelessReady();
    }
}

// ===================================================================
// WIFI CLIENT (STATION MODE) FUNCTIONS
// ===================================================================

// Check if wlan0 is a USB WiFi adapter
// Returns true if USB, false if onboard or check fails
function isUsbWifiAdapter() {
    try {
        var linkPath = execSync(checkInterfaceLink, { encoding: 'utf8' }).trim();
        return linkPath.includes('usb');
    } catch (e) {
        loggerDebug("Could not determine if wlan0 is USB: " + e);
        return false;
    }
}

// Query USB WiFi adapter hardware capabilities
function queryUsbWifiCapabilities() {
    var capabilities = {
        supportsAP: false,
        supportsStation: true,
        supportsConcurrent: false,
        maxInterfaces: 1,
        chipset: 'unknown'
    };
    
    try {
        var iwListOutput = execSync(iwList, { encoding: 'utf8', timeout: EXEC_TIMEOUT_LONG });
        var modesMatch = iwListOutput.match(/Supported interface modes:([\s\S]*?)(?=\n\s*Band|$)/);
        if (modesMatch && modesMatch[1]) {
            capabilities.supportsAP = modesMatch[1].includes('AP');
            capabilities.supportsStation = modesMatch[1].includes('managed') || modesMatch[1].includes('station');
        }
        var comboMatch = iwListOutput.match(/valid interface combinations:([\s\S]*?)(?=\n\n)/i);
        if (comboMatch && comboMatch[1]) {
            var hasAP = comboMatch[1].includes('AP');
            var hasSTA = comboMatch[1].includes('station') || comboMatch[1].includes('managed');
            capabilities.supportsConcurrent = (hasAP && hasSTA);
        }
        try {
            var deviceInfo = execSync('readlink ' + SYS_CLASS_NET + '/' + wlan + '/device', { encoding: 'utf8' }).trim();
            if (deviceInfo) capabilities.chipset = deviceInfo.split('/').pop();
        } catch (e) {}
    } catch (e) {
        loggerInfo("Could not query USB capabilities: " + e);
    }
    return capabilities;
}

// Known chipset issues database
function getChipsetIssues(chipset) {
    var known = {
        'RTL8822BU': {
            issue: 'AP mode beacon transmission fails',
            recommendation: 'Use station mode only'
        }
    };
    for (var k in known) {
        if (chipset.includes(k)) return known[k];
    }
    return null;
}

// Log USB WiFi capabilities
function logUsbWifiCapabilities(caps) {
    loggerInfo("USB WiFi Capabilities:");
    loggerInfo("  Chipset: " + caps.chipset);
    loggerInfo("  AP mode: " + (caps.supportsAP ? "Yes" : "No"));
    loggerInfo("  Concurrent: " + (caps.supportsConcurrent ? "Yes" : "No"));
    var issues = getChipsetIssues(caps.chipset);
    if (issues) {
        loggerInfo("  Known issue: " + issues.issue);
        loggerInfo("  " + issues.recommendation);
    }
}

// Notify user of USB limitations
function notifyUsbWifiLimitations(caps) {
    if (!caps.supportsAP) {
        loggerInfo("TOAST: USB adapter does not support hotspot mode");
    }
    if (getChipsetIssues(caps.chipset)) {
        loggerInfo("TOAST: Known chipset limitations detected");
    }
}


// Start WiFi client (station) mode - connects to configured AP
// VERSION 19 - STAGE 1 INTEGRATION:
// - Synchronizes with udev rename operations
// - Validates interface identity and readiness
// - Eliminates blind polling and arbitrary waits
// - Provides diagnostic information on failures
function startAP(callback) {
    loggerInfo("Stopped hotspot (if there)..");
    launch(ifdeconfig, "ifdeconfig", true, function (err) {
        loggerDebug("Conf " + ifdeconfig);
        
        // STAGE 1: Wait for udev to complete any pending rename operations
        // This prevents wpa_supplicant from binding to interface mid-rename
        waitForUdevSettle(5000, function(udevErr) {
            
            // STAGE 1: Validate interface is ready before proceeding
            // Checks: interface exists, driver loaded, not in unknown state
            var validation = validateInterfaceReady(wlan);
            
            if (!validation.ready) {
                loggerInfo("STAGE 1 VALIDATION FAILED: " + wlan + " not ready - reason: " + validation.reason);
                
                // Try waiting for interface to become ready
                waitForInterfaceReady(wlan, 8000, function(waitErr, finalValidation) {
                    if (waitErr || !finalValidation.ready) {
                        loggerInfo("ERROR: " + wlan + " failed to become ready, cannot start WiFi client mode");
                        wpaerr = 1;
                        return callback(new Error('Interface validation failed: ' + validation.reason));
                    }
                    
                    // Interface became ready, continue
                    loggerInfo("STAGE 1: " + wlan + " became ready after waiting");
                    proceedWithWpaSupplicant(finalValidation, callback);
                });
                return;
            }
            
            // Interface is ready immediately
            loggerInfo("STAGE 1: " + wlan + " validated and ready (MAC: " + validation.mac + ", USB: " + validation.isUSB + ")");
            proceedWithWpaSupplicant(validation, callback);
        });
    });
}

// Helper function to launch wpa_supplicant after validation passes
function proceedWithWpaSupplicant(validation, callback) {
    // Cache interface identity for later verification
    var initialMAC = validation.mac;
    var initialIsUSB = validation.isUSB;
    
    launch(wpasupp, "wpa supplicant", true, function (err) {
        loggerDebug("wpasupp " + err);
        wpaerr = err ? 1 : 0;
        
        // STAGE 1: Verify interface identity hasn't changed during wpa_supplicant launch
        if (!verifyInterfaceIdentity(wlan, initialMAC)) {
            loggerInfo("CRITICAL: " + wlan + " identity changed during wpa_supplicant launch!");
            loggerInfo("This indicates udev rename race condition - wpa_supplicant may be bound to wrong device");
            
            // Check if interface was renamed
            var newName = detectInterfaceRename(wlan, initialMAC);
            if (newName) {
                loggerInfo("Original " + wlan + " is now named " + newName);
            }
            
            wpaerr = 1;
            return callback(new Error('Interface identity changed during operation'));
        }
        
        // Bring interface UP first (separate command with own timeout)
        try {
            execSync(SUDO + " " + IFCONFIG + " " + wlan + " up", { encoding: 'utf8', timeout: EXEC_TIMEOUT_SHORT });
            loggerDebug("Brought " + wlan + " interface up");
        } catch (e) {
            loggerDebug("Could not bring interface up: " + e);
        }
        
        // Give interface time to stabilize (1 second)
        try {
            execSync("sleep 1", { encoding: 'utf8', timeout: EXEC_TIMEOUT_SHORT });
        } catch (e) {
            loggerDebug("Sleep interrupted: " + e);
        }
        
        // Tell wpa_supplicant to reconfigure (separate command with own timeout)
        try {
            execSync(wpacli + " reconfigure", { encoding: 'utf8', timeout: EXEC_TIMEOUT_SHORT });
            loggerDebug("Triggered wpa_cli reconfigure");
        } catch (e) {
            loggerDebug("Could not trigger reconfigure: " + e);
        }

        let staticDhcpFile;
                try {
                    staticDhcpFile = fs.readFileSync(WLAN_STATIC, 'utf8');
                    loggerInfo("FIXED IP via wlanstatic");
                } catch (e) {
                    staticDhcpFile = dhclient; // fallback
                    loggerInfo("DHCP IP fallback");
                }

                // STAGE 2: Event-driven wpa_supplicant state monitoring
                // Replaces 30-second polling loop with real-time state detection
                loggerInfo("STAGE 2: Starting event-driven WPA state monitor");
                
                startWpaStateMonitor(wlan, function(finalState, stateData) {
                    if (finalState === 'COMPLETED') {
                        // Connection successful
                        loggerInfo("STAGE 2: Connection successful - " + stateData.message);
                        
                        // Check if this is a USB WiFi adapter
                        if (isUsbWifiAdapter()) {
                            // Query and log capabilities on first detection
                            if (!usbWifiCapabilities) {
                                usbWifiCapabilities = queryUsbWifiCapabilities();
                                logUsbWifiCapabilities(usbWifiCapabilities);
                                notifyUsbWifiLimitations(usbWifiCapabilities);
                            }
                            
                            loggerInfo("Restarting dhcpcd.service for reliable DHCP");
                            try {
                                execSync(restartdhcpcd, { encoding: 'utf8', timeout: EXEC_TIMEOUT_LONG });
                                loggerDebug("dhcpcd.service restarted successfully");
                            } catch (e) {
                                loggerInfo("WARNING: Failed to restart dhcpcd.service: " + e);
                            }
                            setTimeout(function() {
                                callback();
                            }, USB_SETTLE_WAIT);
                        } else {
                            loggerInfo("Onboard WiFi adapter detected, using standard dhcpcd flow");
                            // Wait 1 second then launch dhcpcd
                            setTimeout(function() {
                                launch(staticDhcpFile, "dhclient", false, function() {
                                    // Verify dhcpcd process status
                                    setTimeout(function() {
                                        try {
                                            var dhcpcdCheck = execSync(PGREP + " -f 'dhcpcd.*" + wlan + "'", { encoding: 'utf8' });
                                            loggerDebug("dhcpcd process running for " + wlan + ": " + dhcpcdCheck.trim());
                                            
                                            // Check if dhcpcd actually assigned an IP
                                            setTimeout(function() {
                                                try {
                                                    var ipCheck = execSync(ipAddr + " | " + GREP + " 'inet ' | awk '{print $2}'", { encoding: 'utf8' }).trim();
                                                    if (ipCheck && ipCheck.length > 0) {
                                                        loggerDebug("dhcpcd assigned IP: " + ipCheck);
                                                    } else {
                                                        loggerInfo("WARNING: dhcpcd running but no IP assigned yet");
                                                    }
                                                } catch (e) {
                                                    loggerDebug("IP check failed: " + e);
                                                }
                                            }, 3000);
                                        } catch (e) {
                                            loggerInfo("Warning: dhcpcd may not be managing " + wlan);
                                        }
                                        callback();
                                    }, USB_SETTLE_WAIT);
                                });
                            }, 1000);
                        }
                    } else {
                        // Connection failed - handle based on failure reason
                        var explanation = getFailureExplanation(finalState);
                        loggerInfo("STAGE 2: Connection failed - " + explanation);
                        
                        if (stateData && typeof stateData === 'string') {
                            loggerInfo("STAGE 2: Failure details: " + stateData);
                        }
                        
                        // For INTERFACE_DISABLED, verify interface identity hasn't changed
                        if (finalState === 'INTERFACE_DISABLED') {
                            if (!verifyInterfaceIdentity(wlan, initialMAC)) {
                                loggerInfo("STAGE 2: Interface identity changed - rename race detected");
                            }
                        }
                        
                        // Set flag to skip afterAPStart polling loop
                        // Stage 2 already determined connection failed, no need to poll again
                        stage2Failed = true;
                        loggerInfo("STAGE 2: Skipping afterAPStart loop, proceeding directly to hotspot evaluation");
                        
                        // Proceed to callback which will trigger afterAPStart
                        // afterAPStart will check stage2Failed flag and skip its polling loop
                        callback();
                    }
                });
            });
}

// Wait for wlan0 interface to be down or released (no carrier)
// Polls interface state up to MAX_RETRIES times before proceeding
function waitForWlanRelease(attempt, onReleased) {
    const MAX_RETRIES = 10;
    const RETRY_INTERVAL = 1000;

    try {
        const output = execSync(ipLink).toString();
        if (output.includes('state DOWN') || output.includes('NO-CARRIER')) {
            loggerDebug(wlan + " is released.");
            return onReleased();
        }
    } catch (e) {
        loggerDebug("Error checking " + wlan + ": " + e);
        return onReleased(); // fallback if interface not found
    }

    if (attempt >= MAX_RETRIES) {
        loggerDebug("Timeout waiting for " + wlan + " release.");
        return onReleased();
    }

    setTimeout(function () {
        waitForWlanRelease(attempt + 1, onReleased);
    }, RETRY_INTERVAL);
}

// Stop WiFi client mode by killing dhcpcd and wpa_supplicant
function stopAP(callback) {
    // Use interface-specific patterns to avoid killing eth0 dhcpcd
    loggerDebug("stopAP: BEGIN");
    var startTime = Date.now();
    
    kill(justdhclient, function(err) {
        var dhcpTime = Date.now() - startTime;
        if (err) {
            loggerInfo("stopAP: dhclient kill error (" + dhcpTime + "ms): " + err);
        } else {
            loggerDebug("stopAP: dhclient killed successfully (" + dhcpTime + "ms)");
        }
        
        kill(wpasuppPattern, function(err) {
            var wpaTime = Date.now() - startTime - dhcpTime;
            if (err) {
                loggerInfo("stopAP: wpa_supplicant kill error (" + wpaTime + "ms): " + err);
            } else {
                loggerDebug("stopAP: wpa_supplicant killed successfully (" + wpaTime + "ms)");
            }
            
            var totalTime = Date.now() - startTime;
            loggerDebug("stopAP: END - total time " + totalTime + "ms");
            callback();
        });
    });
}

// Wait for interface release and start AP with retry logic
// Prevents duplicate AP start attempts and implements exponential backoff
function waitForInterfaceReleaseAndStartAP() {
    // Prevent duplicate calls
    if (apStartInProgress) {
        loggerDebug("AP start already in progress, ignoring duplicate call");
        return;
    }

    apStartInProgress = true;

    const MAX_WAIT = 8000;
    const INTERVAL = 1000;
    let waited = 0;

    const wait = () => {
        if (checkInterfaceReleased()) {
            loggerDebug("Interface " + wlan + " released. Proceeding with startAP...");
            startAP(function () {
                if (wpaerr > 0) {
                    retryCount++;
                    loggerInfo(`startAP failed. Retry ${retryCount} of ${maxRetries}`);
                    if (retryCount < maxRetries) {
                        apStartInProgress = false; // Reset before retry
                        setTimeout(waitForInterfaceReleaseAndStartAP, STARTAP_RETRY_DELAY);
                    } else {
                        loggerInfo("startAP reached max retries. Attempting fallback.");
                        apStartInProgress = false;
                        startHotspotFallbackSafe();
                    }
                } else {
                    afterAPStart();
                }
            });
        } else if (waited >= MAX_WAIT) {
            loggerDebug("Timeout waiting for " + wlan + " release. Proceeding with startAP anyway...");
            startAP(function () {
                if (wpaerr > 0) {
                    retryCount++;
                    loggerInfo(`startAP failed. Retry ${retryCount} of ${maxRetries}`);
                    if (retryCount < maxRetries) {
                        apStartInProgress = false; // Reset before retry
                        setTimeout(waitForInterfaceReleaseAndStartAP, STARTAP_RETRY_DELAY);
                    } else {
                        loggerInfo("startAP reached max retries. Attempting fallback.");
                        apStartInProgress = false;
                        startHotspotFallbackSafe();
                    }
                } else {
                    afterAPStart();
                }
            });
        } else {
            waited += INTERVAL;
            setTimeout(wait, INTERVAL);
        }
    };
    wait();
}

// Start connection polling after AP (station mode) is launched
// Polls interface every second to check for IP assignment
// Implements timeout and fallback to hotspot if connection fails
function afterAPStart() {
    loggerInfo("Start ap");
    
    // Signal systemd ready EARLY to prevent timeout killing the service
    // We're starting the connection polling loop, service is operational
    notifyWirelessReady();
    
    // Check if Stage 2 already determined connection failed
    if (stage2Failed) {
        loggerInfo("STAGE 2: Connection already failed, skipping polling loop");
        stage2Failed = false; // Reset flag
        
        // Clear any existing timers
        clearConnectionTimer();
        apStartInProgress = false;
        wirelessFlowInProgress = false;
        
        // Evaluate hotspot conditions directly
        loggerInfo("STAGE 2: Evaluating hotspot condition directly");
        
        const fallbackEnabled = hotspotFallbackCondition();
        const ssidMissing = !isConfiguredSSIDVisible();
        const firstBoot = !hasWirelessConnectionBeenEstablishedOnce();

        if (!isWirelessDisabled() && (fallbackEnabled || ssidMissing || firstBoot)) {
            if (checkConcurrentModeSupport()) {
                loggerInfo('Concurrent AP+STA supported. Starting hotspot without stopping STA.');
                startHotspot(function (err) {
                    if (err) {
                        loggerInfo('Could not start Hotspot Fallback: ' + err);
                    } else {
                        updateNetworkState("hotspot");
                    }
                    notifyWirelessReady();
                });
            } else {
                loggerInfo('No concurrent mode. Stopping STA and starting hotspot.');
                apstopped = 1;
                stopAP(function () {
                    setTimeout(()=> {
                        startHotspot(function (err) {
                            if (err) {
                                loggerInfo('Could not start Hotspot Fallback: ' + err);
                            } else {
                                updateNetworkState("hotspot");
                            }
                            notifyWirelessReady();
                        });
                    }, settleTime);
                });
            }
        } else {
            // Hotspot fallback conditions not met
            // CRITICAL: Check if system is completely inaccessible
            if (!isWiredNetworkActive) {
                // EMERGENCY RECOVERY MODE
                loggerInfo("=== EMERGENCY RECOVERY MODE ===");
                loggerInfo("No network connectivity: Ethernet DOWN, WiFi connection FAILED");
                loggerInfo("Forcing hotspot for system recovery (overriding config settings)");
                loggerInfo("===============================");
                startHotspotFallbackSafe();
            } else {
                // Ethernet is UP - system is accessible via LAN
                loggerInfo("WiFi connection failed, but system accessible via ethernet");
                apstopped = 0;
                updateNetworkState("offline");
                notifyWirelessReady();
            }
        }
        
        return; // Exit early, skip polling loop below
    }
    
    actualTime = 0; // Reset timer

    // Make absolutely sure no old timer exists
    clearConnectionTimer();

    lesstimer = setInterval(()=> {
        actualTime += pollingTime;
        if (wpaerr > 0) {
            actualTime = totalSecondsForConnection + 1;
        }

        if (actualTime > totalSecondsForConnection) {
            // Determine reason for connection failure
            var failureReason = "unknown";
            try {
                var ssidCheck = execSync(iwgetid, { uid: 1000, gid: 1000, encoding: 'utf8' }).replace('\n','');
                if (ssidCheck && ssidCheck.length > 0) {
                    failureReason = "SSID associated but no IP address received from DHCP";
                } else {
                    failureReason = "wpa_supplicant failed to associate with AP";
                }
            } catch (e) {
                failureReason = "wpa_supplicant failed to associate with AP";
            }
            
            loggerInfo("Overtime, connection failed. Reason: " + failureReason);
            loggerInfo("Evaluating hotspot condition.");

            // Clear timer immediately
            clearConnectionTimer();
            apStartInProgress = false; // Reset flag
            wirelessFlowInProgress = false; // Reset flow flag

            const fallbackEnabled = hotspotFallbackCondition();
            const ssidMissing = !isConfiguredSSIDVisible();
            const firstBoot = !hasWirelessConnectionBeenEstablishedOnce();

            if (!isWirelessDisabled() && (fallbackEnabled || ssidMissing || firstBoot)) {
                if (checkConcurrentModeSupport()) {
                    loggerInfo('Concurrent AP+STA supported. Starting hotspot without stopping STA.');
                    startHotspot(function (err) {
                        if (err) {
                            loggerInfo('Could not start Hotspot Fallback: ' + err);
                        } else {
                            updateNetworkState("hotspot");
                        }
                        notifyWirelessReady();
                    });
                } else {
                    loggerInfo('No concurrent mode. Stopping STA and starting hotspot.');
                    apstopped = 1;
                    stopAP(function () {
                        setTimeout(()=> {
                            startHotspot(function (err) {
                                if (err) {
                                    loggerInfo('Could not start Hotspot Fallback: ' + err);
                                } else {
                                    updateNetworkState("hotspot");
                                }
                                notifyWirelessReady();
                            });
                        }, settleTime);
                    });
                }
            } else {
                // Hotspot fallback conditions not met
                // CRITICAL: Check if system is completely inaccessible
                if (!isWiredNetworkActive) {
                    // EMERGENCY RECOVERY MODE
                    // System has NO network connectivity (LAN down, WiFi failed)
                    // Force hotspot regardless of config to allow user access
                    loggerInfo("=== EMERGENCY RECOVERY MODE ===");
                    loggerInfo("No network connectivity: Ethernet DOWN, WiFi connection FAILED");
                    loggerInfo("Forcing hotspot for system recovery (overriding config settings)");
                    loggerInfo("===============================");
                    
                    startHotspotFallbackSafe();
                } else {
                    // Ethernet is UP - system is accessible via LAN
                    // WiFi failed but user can still access via ethernet
                    loggerInfo("WiFi connection failed, but system accessible via ethernet");
                    apstopped = 0;
                    updateNetworkState("offline");
                    notifyWirelessReady();
                }
            }

            return; // Exit callback
        } else {
            var SSID = undefined;
            loggerInfo("trying...");
            
            // Verify wpa_supplicant still running
            try {
                var wpaCheck = execSync(PGREP + " -f 'wpa_supplicant.*" + wlan + "'", { encoding: 'utf8' });
                loggerDebug("wpa_supplicant process active: " + wpaCheck.trim());
                
                // Check if wpa_supplicant has actually connected
                try {
                    var wpaState = execSync(wpacli + " status | " + GREP + " wpa_state", { encoding: 'utf8', timeout: EXEC_TIMEOUT_SHORT }).trim();
                    loggerDebug("wpa_supplicant state: " + wpaState);
                    
                    if (wpaState.includes("COMPLETED")) {
                        loggerDebug("wpa_supplicant reports COMPLETED state");
                    } else {
                        loggerDebug("wpa_supplicant not yet in COMPLETED state");
                    }
                } catch (e) {
                    loggerDebug("Could not query wpa_supplicant state: " + e);
                }
            } catch (e) {
                loggerInfo("ERROR: wpa_supplicant process not found, connection impossible");
                actualTime = totalSecondsForConnection + 1; // Force timeout
                return;
            }
            
            // Try to get SSID but don't depend on it (RTL8822BU has iwgetid issues)
            try {
                SSID = execSync(iwgetid, { uid: 1000, gid: 1000, encoding: 'utf8' }).replace('\n','');
                loggerDebug('iwgetid returned: ----' + SSID + '----');
            } catch (e) {
                loggerDebug('iwgetid returned nothing (may be driver issue, checking IP instead)');
            }

            // ALWAYS check IP regardless of iwgetid result
            ifconfig.status(wlan, function (err, ifstatus) {
                if (err) {
                    loggerDebug("ifconfig.status error: " + err);
                    return;
                }
                
                if (!ifstatus) {
                    loggerDebug("ifconfig.status returned null/undefined");
                    return;
                }
                
                loggerDebug("ifconfig.status returned: " + JSON.stringify(ifstatus));
                
                var hasIPv4 = (ifstatus.ipv4_address != undefined && 
                               ifstatus.ipv4_address.length > 0 && 
                               ifstatus.ipv4_address !== "0.0.0.0");
                var hasIPv6 = (ifstatus.ipv6_address != undefined && 
                               ifstatus.ipv6_address.length > 0 && 
                               ifstatus.ipv6_address !== "::");
                
                loggerInfo("... " + wlan + " IPv4 is " + ifstatus.ipv4_address + ", ipV6 is " + ifstatus.ipv6_address);
                
                if (hasIPv4 || hasIPv6) {
                    if (apstopped == 0) {
                        // Get configured SSID for validation
                        var configuredSSID = undefined;
                        try {
                            var conf = getWirelessConfiguration();
                            configuredSSID = conf.wlanssid?.value;
                        } catch (e) {}
                        
                        // Log connection with SSID if available
                        if (SSID) {
                            loggerInfo('Connected to SSID: ' + SSID);
                            if (configuredSSID && SSID !== configuredSSID) {
                                loggerInfo("WARNING: Connected to wrong SSID. Expected: " + configuredSSID);
                            }
                        } else {
                            loggerInfo('Connected (iwgetid failed but IP assigned - driver compatibility issue)');
                        }
                        
                        loggerInfo("It's done! AP");
                        retryCount = 0;

                        // Clear timer
                        clearConnectionTimer();
                        apStartInProgress = false; // Reset flag
                        wirelessFlowInProgress = false; // Reset flow flag

                        updateNetworkState("ap");
                        restartAvahi();
                        saveWirelessConnectionEstablished();
                        notifyWirelessReady();
                    }
                }
            });
        }
    }, pollingTime * 1000);
}

// ===================================================================
// FLOW CONTROL FUNCTIONS
// ===================================================================

// Main wireless flow initialization
// Handles various startup scenarios:
// - Forced hotspot mode (/tmp/forcehotspot)
// - Unconfigured network (first boot)
// - Wireless disabled
// - Single network mode with active ethernet
// - Normal WiFi client connection
function startFlow() {
    // Prevent duplicate flow starts
    if (wirelessFlowInProgress) {
        loggerDebug("Wireless flow already in progress, ignoring duplicate call");
        return;
    }
    wirelessFlowInProgress = true;

    // Stop any existing flow first
    clearConnectionTimer();

    actualTime = 0;
    apstopped = 0;
    apStartInProgress = false;
    wpaerr = 0;

    var directhotspot = false;
    try {
        var netconfigured = fs.statSync(NET_CONFIGURED);
        if (!netconfigured) {
            loggerInfo("netconfigured file invalid, starting hotspot");
            directhotspot = true;
        }
    } catch (e) {
        loggerInfo("netconfigured file not found, starting hotspot");
        directhotspot = true;
    }

    try {
        fs.accessSync(FORCE_HOTSPOT_FLAG, fs.F_OK);
        var hotspotForce = true;
        fs.unlinkSync(FORCE_HOTSPOT_FLAG)
    } catch (e) {
        var hotspotForce = false;
    }
    if (hotspotForce) {
        loggerInfo('Wireless networking forced to hotspot mode');
        startHotspotForce(function () {
            notifyWirelessReady();
        });
    } else if (isWirelessDisabled()) {
        // Emergency override - if no ethernet, force hotspot despite WiFi disabled
        if (!isWiredNetworkActive) {
            loggerInfo('=== EMERGENCY OVERRIDE ===');
            loggerInfo('WiFi DISABLED in config, but no ethernet available');
            loggerInfo('Forcing hotspot for system accessibility');
            loggerInfo('User can disable hotspot after connecting via emergency AP');
            loggerInfo('==========================');
            startHotspotFallbackSafe();
        } else {
            loggerInfo('Wireless Networking DISABLED, not starting wireless flow');
            notifyWirelessReady();
        }
    } else if (singleNetworkMode && isWiredNetworkActive) {
        // Keep wlan0 UP without IP for scanning capability
        loggerInfo('Single Network Mode: Ethernet active, maintaining WiFi scan capability');
        keepWlanUpWithoutIP(function(err) {
            if (err) {
                loggerInfo('Failed to maintain scan mode: ' + err);
                loggerInfo('Falling back to interface DOWN');
            }
            notifyWirelessReady();
        });
    } else if (directhotspot){
        // Use verified hotspot start with retry logic for first boot
        // Plain startHotspot() doesn't verify hostapd actually started
        loggerInfo('First boot: Starting hotspot with verification');
        startHotspotFallbackSafe();
    } else {
        loggerInfo("Start wireless flow");
        waitForInterfaceReleaseAndStartAP();
    }
}

// Stop all wireless operations (client and hotspot)
function stop(callback) {
    stopAP(function() {
        stopHotspot(callback);
    });
}

// ===================================================================
// SNM SCAN MODE FUNCTIONS
// ===================================================================

// Keep wlan0 UP without IP for scanning capability (SNM ethernet active)
function keepWlanUpWithoutIP(callback) {
    // Check if wireless is disabled in config
    if (isWirelessDisabled()) {
        loggerInfo("SNM: WiFi disabled in config, not starting scan mode");
        loggerInfo("SNM: Ethernet has exclusive access");
        return callback(null);
    }
    
    loggerInfo("SNM: Maintaining wlan0 UP without IP (scan mode)");
    loggerInfo("SNM: Users can configure WiFi via WebUI while ethernet is active");
    
    // Step 1: Stop any existing connections and clear state
    stopAP(function(err) {
        if (err) loggerInfo("keepWlanUpWithoutIP: stopAP error: " + err);
        
        // Step 2: Bring interface UP
        launch(ifconfigUp, "ifconfig_up", true, function(err) {
            if (err) {
                loggerInfo("keepWlanUpWithoutIP: Failed to bring interface UP: " + err);
                return callback(err);
            }
            
            loggerDebug("keepWlanUpWithoutIP: Interface brought UP");
            
            // Step 3: Flush any existing IP addresses
            var flushCmd = SUDO + " " + IP + " addr flush dev " + wlan;
            launch(flushCmd, "flush_ip", true, function(err) {
                if (err) loggerDebug("keepWlanUpWithoutIP: IP flush error (may be expected): " + err);
                
                loggerDebug("keepWlanUpWithoutIP: IP addresses flushed");
                
                // Step 4: Start wpa_supplicant (for scanning capability)
                launch(wpasupp, "wpa_supplicant", true, function(err) {
                    if (err) {
                        loggerInfo("keepWlanUpWithoutIP: wpa_supplicant failed: " + err);
                        return callback(err);
                    }
                    
                    loggerDebug("keepWlanUpWithoutIP: wpa_supplicant started");
                    
                    // Step 5: Tell wpa_supplicant to disconnect (don't associate)
                    // This keeps it in DISCONNECTED state - interface UP, no connection
                    var disconnectCmd = wpacli + " disconnect";
                    launch(disconnectCmd, "wpa_disconnect", true, function(err) {
                        if (err) loggerDebug("keepWlanUpWithoutIP: disconnect command error: " + err);
                        
                        // Calculate transition time for diagnostics
                        if (transitionStartTime > 0) {
                            var transitionTime = Date.now() - transitionStartTime;
                            loggerInfo("SNM: Transition to scan mode completed in " + transitionTime + "ms");
                            transitionStartTime = 0;
                        }
                        
                        loggerInfo("SNM: wlan0 is UP without IP, scan capable");
                        
                        // Write SNM status for backend notification
                        try {
                            fs.writeFileSync(SNM_STATUS_FILE, 'scan_mode', 'utf8');
                        } catch (e) {
                            loggerDebug("Could not write SNM status: " + e);
                        }
                        
                        // Verify final state (diagnostic)
                        verifyWlanScanState();
                        
                        callback(null);
                    });
                });
            });
        });
    });
}

// Verify wlan0 is in scan-capable state (UP without IP)
// Verify wlan0 is in correct scan mode state (diagnostic)
function verifyWlanScanState() {
    try {
        // Check interface state
        var linkState = execSync(ipLink, { encoding: 'utf8', timeout: EXEC_TIMEOUT_SHORT });
        var isUP = linkState.includes('state UP');
        var hasCarrier = !linkState.includes('NO-CARRIER');
        
        loggerDebug("wlan0 verification: UP=" + isUP + " CARRIER=" + hasCarrier);
        
        // Check IP address
        var addrState = execSync(ipAddr, { encoding: 'utf8', timeout: EXEC_TIMEOUT_SHORT });
        var hasIPv4 = addrState.match(/inet (\d+\.\d+\.\d+\.\d+)/);
        
        if (hasIPv4) {
            loggerInfo("WARNING: wlan0 has IP " + hasIPv4[1] + " but should have none");
        } else {
            loggerDebug("wlan0 verification: No IP (correct)");
        }
        
        // Check wpa_supplicant state
        var wpaState = execSync(wpacli + " status | " + GREP + " wpa_state", { 
            encoding: 'utf8', 
            timeout: EXEC_TIMEOUT_SHORT 
        }).trim();
        loggerDebug("wlan0 verification: " + wpaState);
        
        if (wpaState.includes("DISCONNECTED") || wpaState.includes("INACTIVE")) {
            loggerDebug("wlan0 verification: PASSED - interface ready for scanning");
        } else {
            loggerInfo("wlan0 state: " + wpaState + " (expected DISCONNECTED or INACTIVE)");
        }
        
    } catch (e) {
        loggerDebug("wlan0 verification error: " + e);
    }
}

// Reconnect WiFi after ethernet disconnect in Single Network Mode
// Uses wpa_cli reconnect for fast transition without full flow restart
// Reconnect WiFi after ethernet disconnected (SNM fast reconnection)
function reconnectWiFiAfterEthernet(callback) {
    loggerInfo("SNM: Ethernet disconnected, reconnecting WiFi");
    
    // Check if wpa_supplicant is running
    try {
        var wpaCheck = execSync(PGREP + " -f 'wpa_supplicant.*" + wlan + "'", { 
            encoding: 'utf8',
            timeout: EXEC_TIMEOUT_SHORT 
        });
        loggerDebug("reconnectWiFi: wpa_supplicant already running: " + wpaCheck.trim());
    } catch (e) {
        // wpa_supplicant not running, need to start it
        loggerInfo("reconnectWiFi: wpa_supplicant not running, starting full wireless flow");
        return initializeWirelessFlow();
    }
    
    // wpa_supplicant is running, just reconnect
    var reconnectCmd = wpacli + " reconnect";
    launch(reconnectCmd, "wpa_reconnect", true, function(err) {
        if (err) {
            loggerInfo("reconnectWiFi: Reconnect command failed: " + err);
            loggerInfo("reconnectWiFi: Falling back to full wireless flow restart");
            wirelessFlowInProgress = false;  // Reset to allow restart
            return initializeWirelessFlow();
        }
        
        loggerInfo("reconnectWiFi: WiFi reconnection triggered");
        
        // Wait for connection to establish before launching dhcpcd
        // Give wpa_supplicant time to associate and authenticate
        setTimeout(function() {
            // Check connection state
            try {
                var wpaState = execSync(wpacli + " status | " + GREP + " wpa_state", {
                    encoding: 'utf8',
                    timeout: EXEC_TIMEOUT_SHORT
                }).trim();
                
                loggerDebug("reconnectWiFi: WiFi state after reconnect: " + wpaState);
                
                if (wpaState.includes("COMPLETED")) {
                    loggerInfo("reconnectWiFi: WiFi reconnected successfully");
                    
                    // Check if this is a USB WiFi adapter
                    if (isUsbWifiAdapter()) {
                        // FIX v4.0-rc3: Use dhcpcd -n to force fresh lease instead of service restart
                        // Service restart may attempt to rebind old/expired lease which can fail or timeout
                        // The -n flag forces new DISCOVER/REQUEST cycle instead of rebind attempt
                        loggerInfo("reconnectWiFi: USB adapter detected, requesting fresh DHCP lease");
                        try {
                            var freshDhcpCmd = SUDO + ' ' + DHCPCD + ' -n ' + wlan;
                            execSync(freshDhcpCmd, { encoding: 'utf8', timeout: EXEC_TIMEOUT_LONG });
                            loggerDebug("reconnectWiFi: Fresh DHCP lease requested for " + wlan);
                        } catch (e) {
                            loggerInfo("reconnectWiFi: WARNING - Failed to request fresh DHCP: " + e);
                        }
                        setTimeout(function() {
                            // Calculate transition time for diagnostics
                            if (transitionStartTime > 0) {
                                var reconnectTime = Date.now() - transitionStartTime;
                                loggerInfo("SNM: WiFi reconnection completed in " + reconnectTime + "ms");
                                transitionStartTime = 0;
                            }
                            
                            loggerInfo("reconnectWiFi: WiFi reconnection complete with USB adapter");
                            updateNetworkState("ap");
                            restartAvahi();
                            if (callback) callback(null);
                        }, USB_SETTLE_WAIT);
                    } else {
                        // Launch dhcpcd to get IP address
                        let staticDhcpFile;
                        try {
                            staticDhcpFile = fs.readFileSync(WLAN_STATIC, 'utf8');
                            loggerInfo("reconnectWiFi: Using static IP configuration");
                        } catch (e) {
                            staticDhcpFile = dhclient;
                            loggerInfo("reconnectWiFi: Using DHCP for IP");
                        }
                        
                        launch(staticDhcpFile, "dhclient", false, function() {
                            // Calculate transition time for diagnostics
                            if (transitionStartTime > 0) {
                                var reconnectTime = Date.now() - transitionStartTime;
                                loggerInfo("SNM: WiFi reconnection completed in " + reconnectTime + "ms");
                                transitionStartTime = 0;
                            }
                            
                            loggerInfo("reconnectWiFi: WiFi reconnection complete, obtaining IP");
                            updateNetworkState("ap");
                            restartAvahi();
                            if (callback) callback(null);
                        });
                    }
                    
                } else {
                    loggerInfo("reconnectWiFi: WiFi reconnect incomplete (" + wpaState + "), reinitializing wireless flow");
                    wirelessFlowInProgress = false;  // Reset to allow restart
                    initializeWirelessFlow();
                }
                
            } catch (e) {
                loggerInfo("reconnectWiFi: Could not verify WiFi state: " + e);
                loggerInfo("reconnectWiFi: Falling back to full wireless flow");
                wirelessFlowInProgress = false;  // Reset to allow restart
                initializeWirelessFlow();
            }
            
        }, RECONNECT_WAIT); // Wait for wpa_supplicant association
    });
}

// Clear the connection polling timer to prevent memory leaks
function clearConnectionTimer() {
    if (lesstimer) {
        clearInterval(lesstimer);
        lesstimer = null;
        loggerDebug("Cleared connection timer");
    }
}

// ===================================================================
// STAGE 1 MODULES: INTERFACE IDENTITY & STATE TRACKING
// ===================================================================

// ===================================================================
// MODULE 1: UDEV COORDINATOR
// Synchronizes with udev rename operations and device initialization
// ===================================================================

// Wait for udev to complete all pending events
// Returns immediately if no events pending
// Times out after specified duration to prevent indefinite blocking
function waitForUdevSettle(timeout, callback) {
    timeout = timeout || 10000; // 10 second default max wait
    var timeoutSeconds = Math.floor(timeout / 1000);
    
    loggerDebug("UdevCoordinator: Waiting for udev to settle (max " + timeoutSeconds + "s)");
    
    try {
        var startTime = Date.now();
        execSync('udevadm settle --timeout=' + timeoutSeconds, { 
            encoding: 'utf8', 
            timeout: timeout 
        });
        var elapsed = Date.now() - startTime;
        loggerDebug("UdevCoordinator: udev settled in " + elapsed + "ms");
        callback(null);
    } catch (e) {
        loggerInfo("UdevCoordinator: udev settle timeout or error: " + e);
        // Not fatal - proceed anyway, validation will catch issues
        callback(null);
    }
}

// Check if udev queue is empty (no pending events)
function isUdevQueueEmpty() {
    try {
        var result = execSync('udevadm settle --timeout=0', { encoding: 'utf8' });
        loggerDebug("UdevCoordinator: udev queue is empty");
        return true;
    } catch (e) {
        loggerDebug("UdevCoordinator: udev queue has pending events");
        return false;
    }
}

// ===================================================================
// MODULE 2: INTERFACE VALIDATOR
// Verifies interface physical identity and operational readiness
// ===================================================================

// Get current physical identity of wlan0 (MAC address)
// Returns null if interface doesn't exist
function getInterfaceMAC(interfaceName) {
    try {
        var mac = fs.readFileSync('/sys/class/net/' + interfaceName + '/address', 'utf8').trim();
        return mac;
    } catch (e) {
        loggerDebug("InterfaceValidator: Cannot read MAC for " + interfaceName + ": " + e);
        return null;
    }
}

// Get physical bus path (determines if USB or onboard)
// Returns path like "../../devices/platform/..." or null
function getInterfaceBusPath(interfaceName) {
    try {
        var linkPath = fs.readlinkSync('/sys/class/net/' + interfaceName).trim();
        return linkPath;
    } catch (e) {
        loggerDebug("InterfaceValidator: Cannot read bus path for " + interfaceName + ": " + e);
        return null;
    }
}

// Check if interface is USB device
function isInterfaceUSB(interfaceName) {
    var busPath = getInterfaceBusPath(interfaceName);
    if (!busPath) return false;
    return busPath.includes('usb');
}

// Get interface operational state flags
// Returns object with state information or null
function getInterfaceOperState(interfaceName) {
    try {
        var operstate = fs.readFileSync('/sys/class/net/' + interfaceName + '/operstate', 'utf8').trim();
        var flags = fs.readFileSync('/sys/class/net/' + interfaceName + '/flags', 'utf8').trim();
        var carrier = '0';
        try {
            carrier = fs.readFileSync('/sys/class/net/' + interfaceName + '/carrier', 'utf8').trim();
        } catch (e) {
            // Carrier file doesn't exist if interface is down
        }
        
        return {
            operstate: operstate,      // 'up', 'down', 'unknown', 'dormant'
            flags: parseInt(flags, 16), // Hex flags
            carrier: carrier === '1'    // Physical link present
        };
    } catch (e) {
        loggerDebug("InterfaceValidator: Cannot read operstate for " + interfaceName + ": " + e);
        return null;
    }
}

// Validate interface is ready for wpa_supplicant binding
// Checks: exists, driver loaded, not in use by other process
function validateInterfaceReady(interfaceName) {
    loggerDebug("InterfaceValidator: Validating " + interfaceName + " readiness");
    
    // Check interface exists
    var mac = getInterfaceMAC(interfaceName);
    if (!mac) {
        loggerInfo("InterfaceValidator: FAIL - " + interfaceName + " does not exist");
        return { ready: false, reason: 'interface_not_found' };
    }
    
    // Check operational state
    var state = getInterfaceOperState(interfaceName);
    if (!state) {
        loggerInfo("InterfaceValidator: FAIL - cannot read " + interfaceName + " state");
        return { ready: false, reason: 'state_unreadable' };
    }
    
    // Interface must not be 'unknown' - indicates driver issue
    if (state.operstate === 'unknown') {
        loggerInfo("InterfaceValidator: FAIL - " + interfaceName + " driver not initialized (operstate=unknown)");
        return { ready: false, reason: 'driver_not_ready' };
    }
    
    // Check if interface is being renamed (operstate would be 'down' during rename)
    // This is a heuristic - if interface just appeared and is already down, might be mid-rename
    var busPath = getInterfaceBusPath(interfaceName);
    loggerDebug("InterfaceValidator: " + interfaceName + " MAC=" + mac + " operstate=" + state.operstate + " USB=" + (busPath && busPath.includes('usb')));
    
    // Interface is ready
    loggerInfo("InterfaceValidator: READY - " + interfaceName + " is ready for operations");
    return { 
        ready: true, 
        mac: mac, 
        isUSB: busPath && busPath.includes('usb'),
        operstate: state.operstate 
    };
}

// Wait for interface to become ready with polling fallback
// This is a safety mechanism - should rarely be needed with udev settle
function waitForInterfaceReady(interfaceName, maxWaitMs, callback) {
    var startTime = Date.now();
    var attempts = 0;
    var maxAttempts = Math.floor(maxWaitMs / 500); // Check every 500ms
    
    loggerDebug("InterfaceValidator: Waiting for " + interfaceName + " to become ready (max " + (maxWaitMs/1000) + "s)");
    
    function checkReady() {
        attempts++;
        var validation = validateInterfaceReady(interfaceName);
        
        if (validation.ready) {
            var elapsed = Date.now() - startTime;
            loggerInfo("InterfaceValidator: " + interfaceName + " became ready after " + elapsed + "ms");
            return callback(null, validation);
        }
        
        if (attempts >= maxAttempts) {
            var elapsed = Date.now() - startTime;
            loggerInfo("InterfaceValidator: TIMEOUT waiting for " + interfaceName + " after " + elapsed + "ms (reason: " + validation.reason + ")");
            return callback(new Error('Timeout waiting for interface ready: ' + validation.reason), validation);
        }
        
        // Wait 500ms and check again
        setTimeout(checkReady, INTERFACE_CHECK_INTERVAL);
    }
    
    checkReady();
}

// ===================================================================
// MODULE 3: INTERFACE MONITOR
// Tracks interface state changes and provides identity verification
// ===================================================================

// Interface descriptor cache
var interfaceCache = {};

// Update interface cache with current state
function updateInterfaceCache(interfaceName) {
    var mac = getInterfaceMAC(interfaceName);
    if (!mac) {
        delete interfaceCache[interfaceName];
        return null;
    }
    
    var descriptor = {
        name: interfaceName,
        mac: mac,
        isUSB: isInterfaceUSB(interfaceName),
        busPath: getInterfaceBusPath(interfaceName),
        lastSeen: Date.now()
    };
    
    interfaceCache[interfaceName] = descriptor;
    return descriptor;
}

// Get interface descriptor (cached or fresh)
function getInterfaceDescriptor(interfaceName) {
    // Check cache first
    if (interfaceCache[interfaceName]) {
        var cached = interfaceCache[interfaceName];
        var age = Date.now() - cached.lastSeen;
        
        // Cache valid for 5 seconds
        if (age < 5000) {
            return cached;
        }
    }
    
    // Update cache
    return updateInterfaceCache(interfaceName);
}

// Verify interface identity hasn't changed (detect rename)
// Returns true if interface still has same MAC address
function verifyInterfaceIdentity(interfaceName, expectedMAC) {
    var currentMAC = getInterfaceMAC(interfaceName);
    
    if (!currentMAC) {
        loggerInfo("InterfaceMonitor: " + interfaceName + " no longer exists");
        return false;
    }
    
    if (currentMAC !== expectedMAC) {
        loggerInfo("InterfaceMonitor: " + interfaceName + " identity changed! Was " + expectedMAC + ", now " + currentMAC);
        return false;
    }
    
    return true;
}

// Detect if interface was renamed by comparing against cache
function detectInterfaceRename(originalName, currentMAC) {
    // Check if any cached interface has the current MAC
    for (var name in interfaceCache) {
        var descriptor = interfaceCache[name];
        if (descriptor.mac === currentMAC && name !== originalName) {
            loggerInfo("InterfaceMonitor: Detected rename: " + originalName + " -> " + name + " (MAC: " + currentMAC + ")");
            return name;
        }
    }
    return null;
}

// ===================================================================
// STAGE 2 MODULE: WPA STATE MACHINE
// Event-driven wpa_supplicant monitoring and state management
// Note: WPA_STATES, WPA_STATE_TIMEOUTS, and wpaStateContext are defined
// in the constants section at the top of this file
// ===================================================================

// Monitor wpa_supplicant state changes via wpa_cli status polling
// This is a simplified event monitor - full event-driven via wpa_cli -a would require
// creating an action script file, which adds deployment complexity
function startWpaStateMonitor(interfaceName, callback) {
    loggerInfo("WpaStateMachine: Starting state monitor for " + interfaceName);
    
    wpaStateContext.stateCallback = callback;
    wpaStateContext.currentState = null;
    wpaStateContext.consecutiveFailures = 0;
    
    // Poll wpa_supplicant state every 500ms for changes
    var pollInterval = 500;
    var checkCount = 0;
    var maxChecks = 120; // 60 seconds max monitoring
    
    function pollState() {
        checkCount++;
        
        if (checkCount > maxChecks) {
            loggerInfo("WpaStateMachine: Max monitoring duration reached, stopping");
            stopWpaStateMonitor();
            callback('TIMEOUT', null);
            return;
        }
        
        try {
            var status = execSync(WPA_CLI + ' -i ' + interfaceName + ' status', {
                encoding: 'utf8',
                timeout: EXEC_TIMEOUT_SHORT
            });
            
            // Parse wpa_state from status
            var stateMatch = status.match(/wpa_state=([A-Z_0-9]+)/);
            if (stateMatch) {
                var newState = stateMatch[1];
                
                if (newState !== wpaStateContext.currentState) {
                    handleWpaStateTransition(wpaStateContext.currentState, newState, status);
                }
            }
            
            // Continue polling if not stopped
            if (wpaStateContext.monitorProcess) {
                wpaStateContext.monitorProcess = setTimeout(pollState, pollInterval);
            }
            
        } catch (e) {
            loggerDebug("WpaStateMachine: State poll error: " + e);
            // wpa_supplicant may have crashed or been killed
            if (wpaStateContext.stateCallback) {
                stopWpaStateMonitor();
                callback('ERROR', 'wpa_supplicant not responding');
            }
        }
    }
    
    // Start polling
    wpaStateContext.monitorProcess = setTimeout(pollState, pollInterval);
}

// Stop wpa_supplicant state monitoring
function stopWpaStateMonitor() {
    if (wpaStateContext.monitorProcess) {
        clearTimeout(wpaStateContext.monitorProcess);
        wpaStateContext.monitorProcess = null;
    }
    
    if (wpaStateContext.timeoutHandle) {
        clearTimeout(wpaStateContext.timeoutHandle);
        wpaStateContext.timeoutHandle = null;
    }
    
    loggerDebug("WpaStateMachine: State monitor stopped");
}

// Handle wpa_supplicant state transitions
function handleWpaStateTransition(oldState, newState, statusOutput) {
    var now = Date.now();
    var timeInOldState = oldState ? (now - wpaStateContext.stateEnterTime) : 0;
    
    loggerInfo("WpaStateMachine: State transition: " + (oldState || 'NULL') + " -> " + newState + 
               " (duration: " + timeInOldState + "ms)");
    
    // Update context
    wpaStateContext.previousState = oldState;
    wpaStateContext.currentState = newState;
    wpaStateContext.stateEnterTime = now;
    
    // Clear existing timeout
    if (wpaStateContext.timeoutHandle) {
        clearTimeout(wpaStateContext.timeoutHandle);
        wpaStateContext.timeoutHandle = null;
    }
    
    // Handle state-specific logic
    switch (newState) {
        case WPA_STATES.INTERFACE_DISABLED:
            handleInterfaceDisabledState();
            break;
            
        case WPA_STATES.SCANNING:
            handleScanningState();
            break;
            
        case WPA_STATES.AUTHENTICATING:
            handleAuthenticatingState();
            break;
            
        case WPA_STATES.ASSOCIATING:
            handleAssociatingState();
            break;
            
        case WPA_STATES.FOUR_WAY_HANDSHAKE:
            handleFourWayHandshakeState();
            break;
            
        case WPA_STATES.COMPLETED:
            handleCompletedState(statusOutput);
            break;
            
        case WPA_STATES.DISCONNECTED:
            handleDisconnectedState();
            break;
    }
}

// State-specific handlers

function handleInterfaceDisabledState() {
    loggerInfo("WpaStateMachine: INTERFACE_DISABLED detected - interface or driver issue");
    wpaStateContext.consecutiveFailures++;
    
    // Set timeout for recovery
    wpaStateContext.timeoutHandle = setTimeout(function() {
        loggerInfo("WpaStateMachine: INTERFACE_DISABLED timeout - triggering failure callback");
        stopWpaStateMonitor();
        if (wpaStateContext.stateCallback) {
            wpaStateContext.stateCallback('INTERFACE_DISABLED', 'Interface disabled - possible rename race or driver issue');
        }
    }, WPA_STATE_TIMEOUTS.INTERFACE_DISABLED);
}

function handleScanningState() {
    loggerDebug("WpaStateMachine: SCANNING - looking for networks");
    
    // Set timeout for scanning
    wpaStateContext.timeoutHandle = setTimeout(function() {
        loggerInfo("WpaStateMachine: SCANNING timeout - network not found");
        wpaStateContext.consecutiveFailures++;
        stopWpaStateMonitor();
        if (wpaStateContext.stateCallback) {
            wpaStateContext.stateCallback('SCAN_FAILED', 'Network not found after scanning');
        }
    }, WPA_STATE_TIMEOUTS.SCANNING);
}

function handleAuthenticatingState() {
    loggerDebug("WpaStateMachine: AUTHENTICATING - attempting authentication");
    
    // Set timeout for authentication
    wpaStateContext.timeoutHandle = setTimeout(function() {
        loggerInfo("WpaStateMachine: AUTHENTICATING timeout - authentication failed");
        wpaStateContext.consecutiveFailures++;
        stopWpaStateMonitor();
        if (wpaStateContext.stateCallback) {
            wpaStateContext.stateCallback('AUTH_FAILED', 'Authentication timeout - check password');
        }
    }, WPA_STATE_TIMEOUTS.AUTHENTICATING);
}

function handleAssociatingState() {
    loggerDebug("WpaStateMachine: ASSOCIATING - attempting association");
    
    // Set timeout for association
    wpaStateContext.timeoutHandle = setTimeout(function() {
        loggerInfo("WpaStateMachine: ASSOCIATING timeout - association failed");
        wpaStateContext.consecutiveFailures++;
        stopWpaStateMonitor();
        if (wpaStateContext.stateCallback) {
            wpaStateContext.stateCallback('ASSOC_FAILED', 'Association timeout');
        }
    }, WPA_STATE_TIMEOUTS.ASSOCIATING);
}

function handleFourWayHandshakeState() {
    loggerDebug("WpaStateMachine: 4WAY_HANDSHAKE - performing key exchange");
    
    // Set timeout for 4-way handshake
    wpaStateContext.timeoutHandle = setTimeout(function() {
        loggerInfo("WpaStateMachine: 4WAY_HANDSHAKE timeout - wrong password or PSK issue");
        wpaStateContext.consecutiveFailures++;
        stopWpaStateMonitor();
        if (wpaStateContext.stateCallback) {
            wpaStateContext.stateCallback('HANDSHAKE_FAILED', 'Wrong password or PSK mismatch');
        }
    }, WPA_STATE_TIMEOUTS.FOUR_WAY_HANDSHAKE);
}

function handleCompletedState(statusOutput) {
    loggerInfo("WpaStateMachine: COMPLETED - connection successful");
    wpaStateContext.consecutiveFailures = 0;
    
    // Extract SSID from status
    var ssidMatch = statusOutput.match(/ssid=([^\n]+)/);
    var ssid = ssidMatch ? ssidMatch[1] : 'unknown';
    
    // Stop monitoring and report success
    stopWpaStateMonitor();
    if (wpaStateContext.stateCallback) {
        wpaStateContext.stateCallback('COMPLETED', {
            ssid: ssid,
            message: 'Connected to ' + ssid
        });
    }
}

function handleDisconnectedState() {
    loggerDebug("WpaStateMachine: DISCONNECTED - not associated");
    wpaStateContext.consecutiveFailures++;
    
    // This is normal during connection attempt, don't timeout immediately
    // Just log it and let other states handle timeouts
}

// Get human-readable explanation for failure reason
function getFailureExplanation(reason) {
    var explanations = {
        'INTERFACE_DISABLED': 'WiFi interface disabled - possible hardware or driver issue',
        'SCAN_FAILED': 'Network not found - check SSID and signal strength',
        'AUTH_FAILED': 'Authentication failed - check network configuration',
        'ASSOC_FAILED': 'Association failed - AP may be rejecting connection',
        'HANDSHAKE_FAILED': 'Wrong password or security configuration mismatch',
        'TIMEOUT': 'Connection attempt timed out',
        'ERROR': 'wpa_supplicant error or crash'
    };
    
    return explanations[reason] || 'Unknown failure: ' + reason;
}

// ===================================================================
// UTILITY FUNCTIONS
// ===================================================================

// Check if wlan0 interface has been released (DOWN or NO-CARRIER)
function checkInterfaceReleased() {
    try {
        const output = execSync(ipLink).toString();
        return output.includes('state DOWN') || output.includes('NO-CARRIER');
    } catch (e) {
        return false;
    }
}

// Check if configured SSID is visible in scan results
// Used to determine if hotspot fallback should be enabled
function isConfiguredSSIDVisible() {
    try {
        const config = getWirelessConfiguration();
        const ssid = config.wlanssid?.value;
        const scan = execSync(iwScan + " | " + GREP + " SSID:", { encoding: 'utf8' });
        return ssid && scan.includes(ssid);
    } catch (e) {
        return false;
    }
}

// Check network status for diagnostics
function wstatus(param) {
    if (param) {
        loggerDebug("querying");
    }
}

// Restart Avahi mDNS service for network discovery
// Avahi needs restart after IP change to broadcast correctly
function restartAvahi() {
    try {
        loggerInfo('Restarting avahi-daemon...');
        execSync(SUDO + ' ' + SYSTEMCTL + ' restart avahi-daemon', { encoding: 'utf8' });
        
        // Verify it actually started
        setTimeout(function() {
            try {
                var avahiStatus = execSync(SYSTEMCTL + ' is-active avahi-daemon', { encoding: 'utf8' }).trim();
                if (avahiStatus === 'active') {
                    loggerDebug('Avahi successfully restarted and active');
                } else {
                    loggerInfo('Avahi restart completed but service not active: ' + avahiStatus);
                }
            } catch (e) {
                loggerInfo('Could not verify Avahi status: ' + e);
            }
        }, USB_SETTLE_WAIT);
    } catch (e) {
        loggerInfo('Could not restart Avahi: ' + e);
    }
}

// Notify systemd that wireless service is ready
// Required for Type=notify systemd service
function notifyWirelessReady() {
    exec('systemd-notify --ready', { stdio: 'inherit', shell: '/bin/bash', uid: process.getuid(), gid: process.getgid(), encoding: 'utf8'}, function(error) {
        if (error) {
            loggerInfo('Could not notify systemd about wireless ready: ' + error);
        } else {
            loggerInfo('Notified systemd about wireless ready');
        }
    });
}

// Update network state file for system monitoring
// States: "ap" (client connected), "hotspot" (AP mode), "offline"

// Write network state for node notifier monitoring
function wstatus(nstatus) {
    try {
        thus.exec("echo " + nstatus + " >" + NETWORK_STATUS_FILE, null);
    } catch (e) {
        loggerDebug("Could not write network status: " + e);
    }
}

// Update timestamp to trigger node notifier watch
function refreshNetworkStatusFile() {
    try {
        // Create file if it doesn't exist
        if (!fs.existsSync(NETWORK_STATUS_FILE)) {
            fs.writeFileSync(NETWORK_STATUS_FILE, '', { encoding: 'utf8' });
            loggerDebug("Created network status file: " + NETWORK_STATUS_FILE);
        }
        fs.utimesSync(NETWORK_STATUS_FILE, new Date(), new Date());
        loggerDebug("Refreshed network status timestamp");
    } catch (e) {
        loggerDebug("Could not refresh network status timestamp: " + e);
    }
}

function updateNetworkState(state) {
    if (state === 'ap') {
        try {
            fs.writeFileSync(WLAN_STATUS_FILE, 'connected', 'utf8');
        } catch (e) {}
    } else if (state === 'hotspot') {
        try {
            fs.writeFileSync(WLAN_STATUS_FILE, 'hotspot', 'utf8');
        } catch (e) {}
    } else {
        try {
            fs.writeFileSync(WLAN_STATUS_FILE, 'disconnected', 'utf8');
        } catch (e) {}
    }
    // Notify node notifier
    wstatus(state);
    refreshNetworkStatusFile();
}

// ===================================================================
// LOGGING FUNCTIONS
// ===================================================================

// Logging helper - outputs to both console and /tmp/wireless.log
function loggerDebug(message) {
    if (!debug) return; // Only log debug messages if debug flag is enabled
    var now = new Date();
    // Debug messages go ONLY to file (with timestamp), not console
    fs.appendFileSync(WIRELESS_LOG, "[" + now.toISOString() + "] DEBUG: " + message + "\n");
}

// Logging helper for informational messages
function loggerInfo(message) {
    var now = new Date();
    // Info to console: NO timestamp (journalctl adds it)
    console.log("INFO: " + message);
    // Info to file: WITH timestamp (for manual reading)
    fs.appendFileSync(WIRELESS_LOG, "[" + now.toISOString() + "] INFO: " + message + "\n");
}

// ===================================================================
// CONFIGURATION FUNCTIONS
// ===================================================================

// Read wireless configuration from JSON config file
// Returns configuration object with wireless settings
function getWirelessConfiguration() {
    try {
        var conf = fs.readJsonSync(NETWORK_CONFIG);
        loggerDebug('Loaded configuration');
        loggerDebug('CONF: ' + JSON.stringify(conf));
    } catch (e) {
        loggerDebug('First boot');
        var conf = fs.readJsonSync(VOLUMIO_PLUGINS + '/system_controller/network/config.json');
    }
    return conf
}

// Check if hotspot is disabled in configuration
function isHotspotDisabled() {
    var hotspotConf = getWirelessConfiguration();
    var hotspotDisabled = false;
    if (hotspotConf !== undefined && hotspotConf.enable_hotspot !== undefined && hotspotConf.enable_hotspot.value !== undefined && !hotspotConf.enable_hotspot.value) {
        hotspotDisabled = true;
    }
    return hotspotDisabled
}

// Check if wireless is completely disabled in configuration
function isWirelessDisabled() {
    var wirelessConf = getWirelessConfiguration();
    var wirelessDisabled = false;
    if (wirelessConf !== undefined && wirelessConf.wireless_enabled !== undefined && wirelessConf.wireless_enabled.value !== undefined && !wirelessConf.wireless_enabled.value) {
        wirelessDisabled = true;
    }
    return wirelessDisabled
}

// Check if hotspot fallback should be enabled
// Returns true if:
// - Hotspot fallback is enabled in config
// - Or if this is first boot (no connection established yet)
function hotspotFallbackCondition() {
    var hotspotFallbackConf = getWirelessConfiguration();
    var startHotspotFallback = false;
    if (hotspotFallbackConf !== undefined && hotspotFallbackConf.hotspot_fallback !== undefined && hotspotFallbackConf.hotspot_fallback.value !== undefined && hotspotFallbackConf.hotspot_fallback.value) {
        startHotspotFallback = true;
    }
    if (!startHotspotFallback && !hasWirelessConnectionBeenEstablishedOnce()) {
        startHotspotFallback = true;
    }
    return startHotspotFallback
}

// Save flag file indicating wireless connection was established at least once
function saveWirelessConnectionEstablished() {
    try {
        fs.ensureFileSync(WIRELESS_ESTABLISHED_FLAG)
    } catch (e) {
        loggerDebug('Could not save Wireless Connection Established: ' + e);
    }
}

// Check if wireless connection has been successfully established at least once
function hasWirelessConnectionBeenEstablishedOnce() {
    var wirelessEstablished = false;
    try {
        if (fs.existsSync(WIRELESS_ESTABLISHED_FLAG)) {
            wirelessEstablished = true;
        }
    } catch(err) {}
    return wirelessEstablished
}

// Determine WPA driver string based on hardware platform
// Some platforms (nanopineo2) require wext-only driver
function getWirelessWPADriverString() {
    try {
        var volumioHW = execSync(CAT + " " + OS_RELEASE + " | " + GREP + " ^VOLUMIO_HARDWARE | " + TR + " -d 'VOLUMIO_HARDWARE=\"'", { uid: 1000, gid: 1000, encoding: 'utf8'}).replace('\n','');
    } catch(e) {
        var volumioHW = 'none';
    }
    var fullDriver = 'nl80211,wext';
    var onlyWextDriver = 'wext';
    if (volumioHW === 'nanopineo2') {
        return onlyWextDriver
    } else {
        return fullDriver
    }
}

// Read environment parameters from /volumio/.env
// Checks for SINGLE_NETWORK_MODE and DEBUG_WIRELESS settings
// Note: Single Network Mode is ON by default for production
// Set SINGLE_NETWORK_MODE=false in .env to allow multi-network mode (development only)
function retrieveEnvParameters() {
    // Facility function to read env parameters, without the need for external modules
    try {
        var envParameters = fs.readFileSync(VOLUMIO_ENV, { encoding: 'utf8'});
        
        // Check if Single Network Mode is explicitly disabled (development mode)
        if (envParameters.includes('SINGLE_NETWORK_MODE=false')) {
            singleNetworkMode = false;
            loggerInfo('Multi-Network Mode enabled (development) - both ethernet and wireless can be active simultaneously');
        } else {
            // Default behavior or explicitly set to true
            loggerInfo('Single Network Mode enabled (default) - only one network device can be active at a time between ethernet and wireless');
        }
        
        // Check for debug logging
        if (envParameters.includes('DEBUG_WIRELESS=true')) {
            debug = true;
            loggerInfo('Debug logging enabled via .env');
        }
    } catch(e) {
        // If .env file doesn't exist, use defaults (SNM=true, debug=false)
        loggerInfo('Single Network Mode enabled (default) - only one network device can be active at a time between ethernet and wireless');
        loggerDebug('Could not read ' + VOLUMIO_ENV + ' file: ' + e);
    }
}

// ===================================================================
// REGULATORY DOMAIN FUNCTIONS
// ===================================================================

// Detect and apply appropriate wireless regulatory domain
// Scans for country codes in AP beacons and sets most common one
// Skips scan if regdomain already configured (not 00/0099)
function detectAndApplyRegdomain(callback) {
    if (isWirelessDisabled()) {
        return callback();
    }
    var appropriateRegDom = '00';
    try {
        // Use timeout to prevent blocking startup for too long
        // FIX v4.0-rc3: Use grep -m 1 to limit to first match and split('\n')[0] to handle multi-line output
        // Prevents "Regdomain already set to: 00\n99" appearing on two lines in logs
        var currentRegDomain = execSync(ifconfigUp + " && " + iwRegGet + " | " + GREP + " -m 1 country | " + CUT + " -f1 -d':'", { uid: 1000, gid: 1000, encoding: 'utf8', timeout: EXEC_TIMEOUT_MEDIUM }).replace(/country /g, '').split('\n')[0].trim();
        
        loggerDebug('CURRENT REG DOMAIN: ' + currentRegDomain);
        
        // Only scan if current regdomain is default (00)
        if (currentRegDomain === '00' || currentRegDomain === '0099' || !currentRegDomain) {
            loggerDebug('Current regdomain is default, scanning for appropriate regdomain...');
            var countryCodesInScan = execSync(ifconfigUp + " && " + iwScan + " | " + GREP + " Country: | " + CUT + " -f 2", { uid: 1000, gid: 1000, encoding: 'utf8', timeout: EXEC_TIMEOUT_SCAN }).replace(/Country: /g, '').split('\n');
            var appropriateRegDomain = determineMostAppropriateRegdomain(countryCodesInScan);
            loggerDebug('APPROPRIATE REG DOMAIN: ' + appropriateRegDomain);
            if (isValidRegDomain(appropriateRegDomain) && appropriateRegDomain !== currentRegDomain) {
                applyNewRegDomain(appropriateRegDomain);
            }
        } else {
            loggerInfo('Regdomain already set to: ' + currentRegDomain + ', skipping scan');
        }
    } catch(e) {
        loggerInfo('Failed to determine most appropriate reg domain: ' + e);
    }
    callback();
}

// Apply new wireless regulatory domain
function applyNewRegDomain(newRegDom) {
    loggerInfo('SETTING APPROPRIATE REG DOMAIN: ' + newRegDom);

    try {
        execSync(ifconfigUp + " && " + iwRegSet + " " + newRegDom, { uid: 1000, gid: 1000, encoding: 'utf8'});
        fs.writeFileSync(CRDA_CONFIG, "REGDOMAIN=" + newRegDom);
        loggerInfo('SUCCESSFULLY SET NEW REGDOMAIN: ' + newRegDom)
    } catch(e) {
        loggerInfo('Failed to set new reg domain: ' + e);
    }

}

// Validate regulatory domain format (must be 2-letter country code)
function isValidRegDomain(regDomain) {
    if (regDomain && regDomain.length === 2) {
        return true;
    } else {
        return false;
    }
}

// Determine most frequently occurring regulatory domain from scan results
// Returns the country code that appears most often in beacon frames
function determineMostAppropriateRegdomain(arr) {
    let compare = "";
    let mostFreq = "";
    if (!arr.length) {
        arr = ['00'];
    }
    arr.reduce((acc, val) => {
        if(val in acc){
            acc[val]++;
        }else{
            acc[val] = 1;
        }
        if(acc[val] > compare){
            compare = acc[val];
            mostFreq = val;
        }
        return acc;
    }, {})
    return mostFreq;
}

// ===================================================================
// CONCURRENT MODE SUPPORT
// ===================================================================

// Check if wireless adapter supports concurrent AP+STA mode
// Parses 'iw list' output to determine interface combination support
function checkConcurrentModeSupport() {
    try {
        const output = execSync(iwList, { encoding: 'utf8' });
        const comboRegex = /valid interface combinations([\s\S]*?)(?=\n\n)/i;
        const comboBlock = output.match(comboRegex);

        if (!comboBlock || comboBlock.length < 2) {
            loggerDebug('WIRELESS: No interface combination block found.');
            return false;
        }

        const comboText = comboBlock[1];

        const hasAP = comboText.includes('AP');
        const hasSTA = comboText.includes('station') || comboText.includes('STA');

        if (hasAP && hasSTA) {
            loggerInfo('WIRELESS: Concurrent AP+STA mode supported.');
            return true;
        } else {
            loggerInfo('WIRELESS: Concurrent AP+STA mode NOT supported.');
            return false;
        }
    } catch (err) {
        loggerInfo('WIRELESS: Failed to determine interface mode support: ' + err);
        return false;
    }
}

// ===================================================================
// ETHERNET MONITORING (Single Network Mode)
// ===================================================================

// Start monitoring ethernet status file for Single Network Mode
// Watches /data/eth0status for changes and triggers wireless reinitialization
function startWiredNetworkingMonitor() {
    try {
        fs.accessSync(ETH_STATUS_FILE);
    } catch (error) {
        fs.writeFileSync(ETH_STATUS_FILE, 'disconnected', 'utf8');
    }
    checkWiredNetworkStatus(true);
    fs.watch(ETH_STATUS_FILE, () => {
        checkWiredNetworkStatus();
    });
}

// Check wired network status and reinitialize wireless if needed
// In Single Network Mode, wireless flow restarts when ethernet status changes
function checkWiredNetworkStatus(isFirstStart) {
    try {
        // Validate actual hardware state
        var actualState = 'disconnected';
        try {
            var carrier = fs.readFileSync('/sys/class/net/eth0/carrier', 'utf8').trim();
            if (carrier === '1') {
                actualState = 'connected';
            }
        } catch (e) {
            actualState = 'disconnected';
        }
        
        // Check if state changed BEFORE writing to file
        // Writing to file triggers fs.watch() callback - only write when state actually changes
        if (actualState !== currentEthStatus) {
            // Update file ONLY when state changes (prevents infinite loop)
            try {
                fs.writeFileSync(ETH_STATUS_FILE, actualState, 'utf8');
            } catch (e) {
                loggerDebug('Could not update eth0status: ' + e);
            }
            
            // Start timing transition for diagnostics
            transitionStartTime = Date.now();
            
            // Enhanced transition logging
            loggerInfo("=== SNM TRANSITION ===");
            loggerInfo("Previous ethernet state: " + currentEthStatus);
            loggerInfo("New ethernet state: " + actualState);
            loggerInfo("Single Network Mode: " + (singleNetworkMode ? "enabled" : "disabled"));
            loggerInfo("First start: " + (isFirstStart ? "yes" : "no"));
            
            currentEthStatus = actualState;
            
            if (actualState === 'connected') {
                // Ethernet connected
                isWiredNetworkActive = true;
                loggerInfo("Action: Switch to ethernet (WiFi scan mode)");
                loggerInfo("=== END TRANSITION ===");
                
                if (!isFirstStart && singleNetworkMode) {
                    loggerInfo('SNM: Ethernet connected, switching to ethernet (WiFi scan mode)');
                    
                    // FIX v4.0-rc3: Release wlan0 DHCP lease before transition to prevent stale lease rebind
                    // When reconnecting later, dhcpcd will request fresh lease instead of trying to rebind
                    // expired lease which can fail or timeout on some routers
                    try {
                        loggerDebug('SNM: Releasing wlan0 DHCP lease before ethernet transition');
                        execSync(SUDO + ' ' + DHCPCD + ' -k ' + wlan, { 
                            encoding: 'utf8', 
                            timeout: EXEC_TIMEOUT_SHORT 
                        });
                        loggerDebug('SNM: wlan0 DHCP lease released successfully');
                    } catch (e) {
                        // Non-fatal - may not have active lease
                        loggerDebug('SNM: DHCP release skipped (no active lease): ' + e.message);
                    }
                    
                    // Use setImmediate to break out of fs.watch() callback context
                    // Direct call causes deadlock in thus.exec()
                    loggerDebug('SNM: Scheduling wireless flow restart via setImmediate()');
                    setImmediate(function() {
                        loggerDebug('SNM: setImmediate() callback FIRED - calling initializeWirelessFlow()');
                        try {
                            initializeWirelessFlow();
                        } catch (e) {
                            loggerInfo('SNM: ERROR in initializeWirelessFlow(): ' + e);
                            loggerInfo('SNM: Stack: ' + e.stack);
                        }
                    });
                    loggerDebug('SNM: setImmediate() scheduled, continuing...');
                }
                
            } else {
                // Ethernet disconnected
                isWiredNetworkActive = false;
                loggerInfo("Action: Reconnect WiFi");
                loggerInfo("=== END TRANSITION ===");
                
                if (!isFirstStart && singleNetworkMode) {
                    // Check if WiFi is already connected
                    try {
                        var wifiSSID = execSync(iwgetid, { uid: 1000, gid: 1000, encoding: 'utf8' }).replace('\n','');
                        if (wifiSSID && wifiSSID.length > 0) {
                            loggerInfo('SNM: WiFi already connected to: ' + wifiSSID);
                            return;
                        }
                    } catch (e) {
                        loggerDebug('SNM: Could not check WiFi status: ' + e);
                    }
                    
                    // WiFi not connected, trigger reconnection
                    loggerInfo('SNM: Ethernet disconnected, reconnecting WiFi');
                    // Use setImmediate to break out of fs.watch() callback context
                    loggerDebug('SNM: Scheduling WiFi reconnect via setImmediate()');
                    setImmediate(function() {
                        loggerDebug('SNM: setImmediate() callback FIRED - calling reconnectWiFiAfterEthernet()');
                        try {
                            reconnectWiFiAfterEthernet();
                        } catch (e) {
                            loggerInfo('SNM: ERROR in reconnectWiFiAfterEthernet(): ' + e);
                            loggerInfo('SNM: Stack: ' + e.stack);
                        }
                    });
                    loggerDebug('SNM: setImmediate() scheduled, continuing...');
                }
            }
        }
        
        loggerDebug('checkWiredNetworkStatus: Function complete');
    } catch (e) {
        loggerInfo('Error in checkWiredNetworkStatus: ' + e);
        loggerInfo('Stack: ' + e.stack);
    }
}

// ===================================================================
// INTERFACE VALIDATION
// ===================================================================

if ( ! fs.existsSync(SYS_CLASS_NET + "/" + wlan + "/operstate") ) {
    loggerInfo("ERROR: " + wlan + " does not exist, exiting...");
    process.exit(1);
}
