#!/usr/bin/env node

//===================================================================
// Volumio Network Manager
// Original Copyright: Michelangelo Guarise - Volumio.org
// USB WiFi Fix & Refactoring: Just a Nerd
// Version: 14.0
// 
// Version 14 Changes:
// - Fixed IP change notification for hotspot mode (192.168.211.1)
// - Triggers ip-changed@wlan0.target after static IP assignment  
// - Ensures welcome screen/QR code updates on first boot with hotspot
// 
// Version 13 Changes:
// - Reduced connection timeout from 55 to 30 seconds (faster fallback)
// - Fixed systemd timeout issue: call notifyWirelessReady() early
// - Prevents systemd from killing service before emergency mode triggers
// 
// Version 12 Changes:
// - CRITICAL FIX: Emergency hotspot fallback when system inaccessible
// - Forces hotspot if both ethernet and WiFi down (recovery mode)
// 
// Version 11 Changes:
// - Fixed ethernet state validation (hardware carrier check)
// - Restored node notifier integration
// - Added USB WiFi capability detection
//===================================================================
//===================================================================

// ===================================================================
// CONFIGURATION CONSTANTS
// ===================================================================
var debug = false;
var settleTime = 3000;
var totalSecondsForConnection = 30;
var pollingTime = 1;

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
var justdhclient = SUDO + " " + DHCPCD;
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
// STATE VARIABLES
// ===================================================================
var singleNetworkMode = false;
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
var apstopped = 0

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

// Kill a process by name using pgrep pattern matching
function kill(process, callback) {
    var all = process.split(" ");
    var process = all[0];
    var command = 'kill `' + PGREP + ' -f "^' + process + '"` || true';
    loggerDebug("killing: " + command);
    return thus.exec(command, callback);
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
                
                // Trigger IP change notification for hotspot IP (192.168.211.1)
                // Static IP assignment doesn't trigger dhcpcd hooks, so trigger manually
                // This updates welcome screen, QR code, and /etc/issue display
                try {
                    execSync(SYSTEMCTL + ' start ip-changed@' + wlan + '.target', { encoding: 'utf8', timeout: 2000 });
                    loggerDebug("Triggered ip-changed@" + wlan + ".target for hotspot IP");
                } catch (e) {
                    loggerDebug("Could not trigger ip-changed target: " + e);
                }
                
                launch(starthostapd,"hotspot" , false, function() {
                    updateNetworkState("hotspot");
                    if (callback) callback();
                });
            });
        }
    });
}

// Force start hotspot even if disabled (used for factory reset scenarios)
function startHotspotForce(callback) {
    stopHotspot(function(err) {
        launch(ifconfigHotspot, "confighotspot", true, function(err) {
            loggerDebug("ifconfig " + err);
            
            // Trigger IP change notification for forced hotspot
            try {
                execSync(SYSTEMCTL + ' start ip-changed@' + wlan + '.target', { encoding: 'utf8', timeout: 2000 });
                loggerDebug("Triggered ip-changed@" + wlan + ".target for forced hotspot IP");
            } catch (e) {
                loggerDebug("Could not trigger ip-changed target: " + e);
            }
            
            launch(starthostapd,"hotspot" , false, function() {
                updateNetworkState("hotspot");
                if (callback) callback();
            });
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
                setTimeout(() => startHotspotFallbackSafe(retry + 1), 3000);
            } else {
                loggerInfo("Hotspot failed after maximum retries. System remains offline.");
                notifyWirelessReady();
            }
            return;
        }

        // Verify hostapd status
        try {
            const hostapdStatus = execSync(SYSTEMCTL + " is-active hostapd", { encoding: 'utf8' }).trim();
            if (hostapdStatus !== "active") {
                loggerInfo("Hostapd did not reach active state. Retrying fallback.");
                if (retry + 1 < hotspotMaxRetries) {
                    setTimeout(() => startHotspotFallbackSafe(retry + 1), 3000);
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
                setTimeout(() => startHotspotFallbackSafe(retry + 1), 3000);
            } else {
                loggerInfo("Could not confirm hostapd status. System remains offline.");
                notifyWirelessReady();
            }
        }
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
        var iwListOutput = execSync(iwList, { encoding: 'utf8', timeout: 5000 });
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
// Implements comprehensive flow:
// 1. Deconfigure interface
// 2. Launch wpa_supplicant synchronously
// 3. Poll for COMPLETED state
// 4. Detect USB adapter and restart dhcpcd.service if needed
// 5. Launch dhcpcd for IP assignment
function startAP(callback) {
    loggerInfo("Stopped hotspot (if there)..");
    launch(ifdeconfig, "ifdeconfig", true, function (err) {
        loggerDebug("Conf " + ifdeconfig);
        waitForWlanRelease(0, function () {
            launch(wpasupp, "wpa supplicant", true, function (err) {
                loggerDebug("wpasupp " + err);
                wpaerr = err ? 1 : 0;

                let staticDhcpFile;
                try {
                    staticDhcpFile = fs.readFileSync(WLAN_STATIC, 'utf8');
                    loggerInfo("FIXED IP via wlanstatic");
                } catch (e) {
                    staticDhcpFile = dhclient; // fallback
                    loggerInfo("DHCP IP fallback");
                }

                // Wait for wpa_supplicant to reach COMPLETED state before launching dhcpcd
                var wpaAttempts = 0;
                var maxWpaAttempts = 30; // 30 seconds max
                var wpaInterval = setInterval(function() {
                    wpaAttempts++;
                    try {
                        var wpaState = execSync(wpacli + " status | " + GREP + " wpa_state", 
                                                { encoding: 'utf8', timeout: 2000 }).trim();
                        loggerDebug("wpa_supplicant state check (" + wpaAttempts + "/" + maxWpaAttempts + "): " + wpaState);
                        
                        if (wpaState.includes("COMPLETED")) {
                            loggerInfo("wpa_supplicant COMPLETED state reached");
                            clearInterval(wpaInterval);
                            
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
                                    execSync(restartdhcpcd, { encoding: 'utf8', timeout: 5000 });
                                    loggerDebug("dhcpcd.service restarted successfully");
                                } catch (e) {
                                    loggerInfo("WARNING: Failed to restart dhcpcd.service: " + e);
                                }
                                setTimeout(function() {
                                    callback();
                                }, 2000);
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
                                        }, 2000);
                                    });
                                }, 1000);
                            }
                            return;
                        }
                    } catch (e) {
                        loggerDebug("wpa_cli status check failed: " + e);
                    }
                    
                    if (wpaAttempts >= maxWpaAttempts) {
                        loggerInfo("WARNING: wpa_supplicant timeout waiting for COMPLETED state, launching dhcpcd anyway");
                        clearInterval(wpaInterval);
                        launch(staticDhcpFile, "dhclient", false, callback);
                    }
                }, 1000);
            });
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
    kill(justdhclient, function(err) {
        kill(wpasupp, function(err) {
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
                        setTimeout(waitForInterfaceReleaseAndStartAP, 2000);
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
                        setTimeout(waitForInterfaceReleaseAndStartAP, 2000);
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
                    var wpaState = execSync(wpacli + " status | " + GREP + " wpa_state", { encoding: 'utf8', timeout: 2000 }).trim();
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
        loggerInfo('Wireless Networking DISABLED, not starting wireless flow');
        notifyWirelessReady();
    } else if (singleNetworkMode && isWiredNetworkActive) {
        loggerInfo('Single Network Mode: Wired network active, not starting wireless flow');
        notifyWirelessReady();
    } else if (directhotspot){
        startHotspot(function () {
            notifyWirelessReady();
        });
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

// Clear the connection polling timer to prevent memory leaks
function clearConnectionTimer() {
    if (lesstimer) {
        clearInterval(lesstimer);
        lesstimer = null;
        loggerDebug("Cleared connection timer");
    }
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
        }, 2000);
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
        fs.utimesSync(NETWORK_STATUS_FILE, new Date(), new Date());
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
    var now = new Date();
    console.log("[" + now.toISOString() + "] DEBUG: " + message);
    fs.appendFileSync(WIRELESS_LOG, "[" + now.toISOString() + "] DEBUG: " + message + "\n");
}

// Logging helper for informational messages
function loggerInfo(message) {
    var now = new Date();
    console.log("[" + now.toISOString() + "] INFO: " + message);
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
// Checks for SINGLE_NETWORK_MODE setting
function retrieveEnvParameters() {
    // Facility function to read env parameters, without the need for external modules
    try {
        var envParameters = fs.readFileSync(VOLUMIO_ENV, { encoding: 'utf8'});
        if (envParameters.includes('SINGLE_NETWORK_MODE=true')) {
            singleNetworkMode = true;
            loggerInfo('Single Network Mode enabled, only one network device can be active at a time between ethernet and wireless');
        }
    } catch(e) {
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
        var currentRegDomain = execSync(ifconfigUp + " && " + iwRegGet + " | " + GREP + " country | " + CUT + " -f1 -d':'", { uid: 1000, gid: 1000, encoding: 'utf8', timeout: 3000 }).replace(/country /g, '').replace('\n','');
        
        loggerDebug('CURRENT REG DOMAIN: ' + currentRegDomain);
        
        // Only scan if current regdomain is default (00)
        if (currentRegDomain === '00' || currentRegDomain === '0099' || !currentRegDomain) {
            loggerDebug('Current regdomain is default, scanning for appropriate regdomain...');
            var countryCodesInScan = execSync(ifconfigUp + " && " + iwScan + " | " + GREP + " Country: | " + CUT + " -f 2", { uid: 1000, gid: 1000, encoding: 'utf8', timeout: 10000 }).replace(/Country: /g, '').split('\n');
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
        
        // Update file with actual state
        try {
            fs.writeFileSync(ETH_STATUS_FILE, actualState, 'utf8');
        } catch (e) {
            loggerDebug('Could not update eth0status: ' + e);
        }
        
        // Check if state changed
        if (actualState !== currentEthStatus) {
            currentEthStatus = actualState;
            loggerInfo('Wired network status changed to: ---' + actualState + '---');
            
            if (actualState === 'connected') {
                isWiredNetworkActive = true;
            } else {
                isWiredNetworkActive = false;
            }
            
            if (!isFirstStart && singleNetworkMode) {
                try {
                    var wifiSSID = execSync(iwgetid, { uid: 1000, gid: 1000, encoding: 'utf8' }).replace('\n','');
                    if (wifiSSID && wifiSSID.length > 0 && actualState === 'disconnected') {
                        loggerInfo('WiFi already connected, not reinitializing');
                        return;
                    }
                } catch (e) {}
                
                loggerInfo('Triggering wireless flow restart due to ethernet change');
                initializeWirelessFlow();
            }
        }
    } catch (e) {
        loggerDebug('Error in checkWiredNetworkStatus: ' + e);
    }
}

// ===================================================================
// INTERFACE VALIDATION
// ===================================================================

if ( ! fs.existsSync(SYS_CLASS_NET + "/" + wlan + "/operstate") ) {
    loggerInfo("ERROR: " + wlan + " does not exist, exiting...");
    process.exit(1);
}
