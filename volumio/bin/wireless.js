#!/usr/bin/env node

//Volumio Network Manager - Copyright Michelangelo Guarise - Volumio.org

// Time needed to settle some commands sent to the system like ifconfig
var debug = false;

var settleTime = 3000;
var fs = require('fs-extra')
var thus = require('child_process');
var wlan = "wlan0";
// var dhcpd = "dhcpd";
var dhclient = "/usr/bin/sudo /sbin/dhcpcd";
var justdhclient = "/usr/bin/sudo /sbin/dhcpcd";
var starthostapd = "systemctl start hostapd.service";
var stophostapd = "systemctl stop hostapd.service";
var ifconfigHotspot = "ifconfig " + wlan + " 192.168.211.1 up";
var ifconfigWlan = "ifconfig " + wlan + " up";
var ifdeconfig = "sudo ip addr flush dev " + wlan + " && sudo ifconfig " + wlan + " down";
var execSync = require('child_process').execSync;
var exec = require('child_process').exec;
var ifconfig = require('/volumio/app/plugins/system_controller/network/lib/ifconfig.js');
var wirelessEstablishedOnceFlagFile = '/data/flagfiles/wirelessEstablishedOnce';
var wirelessWPADriver = getWirelessWPADriverString();
if (debug) {
    var wpasupp = "wpa_supplicant -d -s -B -D" + wirelessWPADriver + " -c/etc/wpa_supplicant/wpa_supplicant.conf -i" + wlan;
} else {
    var wpasupp = "wpa_supplicant -s -B -D" + wirelessWPADriver + " -c/etc/wpa_supplicant/wpa_supplicant.conf -i" + wlan;
}
var retryCount = 0;
var maxRetries = 3;

function kill(process, callback) {
    var all = process.split(" ");
    var process = all[0];
    var command = 'kill `pgrep -f "^' + process + '"` || true';
    logger("killing: " + command);
    return thus.exec(command, callback);
}



function launch(fullprocess, name, sync, callback) {
    if (sync) {
        var child = thus.exec(fullprocess, {}, callback);
        child.stdout.on('data', function(data) {
            logger(name + 'stdout: ' + data);
        });

        child.stderr.on('data', function(data) {
            logger(name + 'stderr: ' + data);
        });

        child.on('close', function(code) {
            logger(name + 'child process exited with code ' + code);
        });
    } else {
        var all = fullprocess.split(" ");
        var process = all[0];
        if (all.length > 0) {
            all.splice(0, 1);
        }
        logger("launching " + process + " args: ");
        logger(all);
        var child = thus.spawn(process, all, {});
        child.stdout.on('data', function(data) {
            logger(name + 'stdout: ' + data);
        });

        child.stderr.on('data', function(data) {
            logger(name + 'stderr: ' + data);
        });

        child.on('close', function(code) {
            logger(name + 'child process exited with code ' + code);
        });
        callback();
    }

    return
}

function startHotspot() {
    stopHotspot(function(err) {
        if (isHotspotDisabled()) {
            logger('Hotspot is disabled, not starting it');
            launch(ifconfigWlan, "configwlanup", true, function(err) {
                logger("ifconfig " + err);
            });
        } else {
            launch(ifconfigHotspot, "confighotspot", true, function(err) {
                logger("ifconfig " + err);
                launch(starthostapd, "hotspot", false, function() {
                    updateNetworkState("hotspot");
                });
            });
        }
    });
}

function startHotspotForce() {
    stopHotspot(function(err) {
        logger('Starting Force Hotspot');
        launch(ifconfigHotspot, "confighotspot", true, function(err) {
            logger("ifconfig " + err);
            launch(starthostapd, "hotspot", false, function() {
                updateNetworkState("hotspot");
            });
        });
    });
}

function stopHotspot(callback) {
    launch(stophostapd, "stophotspot" , true, function(err) {
        launch(ifdeconfig, "ifdeconfig", true, callback);
    });
}

function startAP(callback) {
    logger("Stopped hotspot (if there)..");
    launch(ifdeconfig, "ifdeconfig", true, function (err) {
        logger("Conf " + ifdeconfig);
        waitForWlanRelease(0, function () {
            launch(wpasupp, "wpa supplicant", false, function (err) {
                logger("wpasupp " + err);
                wpaerr = err ? 1 : 0;

                let staticDhcpFile;
                try {
                    staticDhcpFile = fs.readFileSync('/data/configuration/wlanstatic', 'utf8');
                    logger("FIXED IP via wlanstatic");
                } catch (e) {
                    staticDhcpFile = dhclient; // fallback
                    logger("DHCP IP fallback");
                }

                launch(staticDhcpFile, "dhclient", false, callback);
            });
        });
    });
}

// Wait for wlan0 interface to be down or released
function waitForWlanRelease(attempt, onReleased) {
    const MAX_RETRIES = 10;
    const RETRY_INTERVAL = 1000;

    try {
        const output = execSync('ip link show wlan0').toString();
        if (output.includes('state DOWN') || output.includes('NO-CARRIER')) {
            logger("wlan0 is released.");
            return onReleased();
        }
    } catch (e) {
        logger("Error checking wlan0: " + e);
        return onReleased(); // fallback if interface not found
    }

    if (attempt >= MAX_RETRIES) {
        logger("Timeout waiting for wlan0 release.");
        return onReleased();
    }

    setTimeout(function () {
        waitForWlanRelease(attempt + 1, onReleased);
    }, RETRY_INTERVAL);
}

function stopAP(callback) {
    kill(justdhclient, function(err) {
        kill(wpasupp, function(err) {
            callback();
        });
    });
}

var wpaerr;
var lesstimer;
var totalSecondsForConnection = 20;
var pollingTime = 1;
var actualTime = 0;
var apstopped = 0

function startFlow() {
    function checkInterfaceReleased() {
        try {
            const output = execSync('ip link show wlan0').toString();
            return output.includes('state DOWN') || output.includes('NO-CARRIER');
        } catch (e) {
            return false;
        }
    }

    function waitForInterfaceReleaseAndStartAP() {
        const MAX_WAIT = 8000;
        const INTERVAL = 1000;
        let waited = 0;

        const wait = () => {
            if (checkInterfaceReleased()) {
                logger("Interface wlan0 released. Proceeding with startAP...");
                startAP(function () {
                    if (wpaerr > 0) {
                        retryCount++;
                        logger(`startAP failed. Retry ${retryCount} of ${maxRetries}`);
                        if (retryCount < maxRetries) {
                            setTimeout(waitForInterfaceReleaseAndStartAP, 2000);
                        } else {
                            logger("startAP reached max retries. Attempting fallback.");
                            startHotspotFallbackSafe();
                        }
                    } else {
                        afterAPStart();
                    }
                });
            } else if (waited >= MAX_WAIT) {
                logger("Timeout waiting for wlan0 release. Proceeding with startAP anyway...");
                startAP(function () {
                    if (wpaerr > 0) {
                        retryCount++;
                        logger(`startAP failed. Retry ${retryCount} of ${maxRetries}`);
                        if (retryCount < maxRetries) {
                            setTimeout(waitForInterfaceReleaseAndStartAP, 2000);
                        } else {
                            logger("startAP reached max retries. Attempting fallback.");
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

    function isConfiguredSSIDVisible() {
        try {
            const config = getWirelessConfiguration();
            const ssid = config.wlanssid?.value;
            const scan = execSync('/usr/bin/sudo /sbin/iw wlan0 scan | grep SSID:', { encoding: 'utf8' });
            return ssid && scan.includes(ssid);
        } catch (e) {
            return false;
        }
    }

    function afterAPStart() {
        logger("Start ap");
        lesstimer = setInterval(() => {
            actualTime += pollingTime;
            if (wpaerr > 0) {
                actualTime = totalSecondsForConnection + 1;
            }

            if (actualTime > totalSecondsForConnection) {
                logger("Overtime, connection failed. Evaluating hotspot condition.");

                const fallbackEnabled = hotspotFallbackCondition();
                const ssidMissing = !isConfiguredSSIDVisible();
                const firstBoot = !hasWirelessConnectionBeenEstablishedOnce();

                if (!isWirelessDisabled() && (fallbackEnabled || ssidMissing || firstBoot)) {
                    if (checkConcurrentModeSupport()) {
                        logger('Concurrent AP+STA supported. Starting hotspot without stopping STA.');
                        startHotspot(function (err) {
                            if (err) {
                                logger('Could not start Hotspot Fallback: ' + err);
                            } else {
                                updateNetworkState("hotspot");
                            }
                        });
                    } else {
                        logger('No concurrent mode. Stopping STA and starting hotspot.');
                        apstopped = 1;
                        clearTimeout(lesstimer);
                        stopAP(function () {
                            setTimeout(() => {
                                startHotspot(function (err) {
                                    if (err) {
                                        logger('Could not start Hotspot Fallback: ' + err);
                                    } else {
                                        updateNetworkState("hotspot");
                                    }
                                });
                            }, settleTime);
                        });
                    }
                } else {
                    apstopped = 0;
                    updateNetworkState("ap");
                    clearTimeout(lesstimer);
                }
            } else {
                let SSID;
                logger("trying...");
                try {
                    SSID = execSync("/usr/bin/sudo /sbin/iwgetid -r", { uid: 1000, gid: 1000, encoding: 'utf8' });
                    logger('Connected to: ----' + SSID + '----');
                } catch (e) {}

                if (SSID !== undefined) {
                    ifconfig.status(wlan, function (err, ifstatus) {
                        logger("... joined AP, wlan0 IPv4 is " + ifstatus.ipv4_address + ", ipV6 is " + ifstatus.ipv6_address);
                        if (((ifstatus.ipv4_address != undefined && ifstatus.ipv4_address.length > "0.0.0.0".length) ||
                             (ifstatus.ipv6_address != undefined && ifstatus.ipv6_address.length > "::".length))) {
                            if (apstopped == 0) {
                                logger("It's done! AP");
                                retryCount = 0;
                                updateNetworkState("ap");
                                clearTimeout(lesstimer);
                                restartAvahi();
                                saveWirelessConnectionEstablished();
                            }
                        }
                    });
                }
            }
        }, pollingTime * 1000);
    }

    try {
        var netconfigured = fs.statSync('/data/configuration/netconfigured');
    } catch (e) {
        var directhotspot = true;
    }

    try {
        fs.accessSync('/tmp/forcehotspot', fs.F_OK);
        var hotspotForce = true;
        fs.unlinkSync('/tmp/forcehotspot');
    } catch (e) {
        var hotspotForce = false;
    }

    if (hotspotForce) {
        logger('Wireless networking forced to hotspot mode');
        startHotspotForce(() => {});
    } else if (isWirelessDisabled()) {
        logger('Wireless Networking DISABLED, not starting wireless flow');
    } else if (directhotspot) {
        startHotspot(() => {});
    } else {
        logger("Start wireless flow");
        waitForInterfaceReleaseAndStartAP();
    }
}

function startHotspotFallbackSafe(retry = 0) {
    const hotspotMaxRetries = 3;

    function handleHotspotResult(err) {
        if (err) {
            logger(`Hotspot launch failed. Retry ${retry + 1} of ${hotspotMaxRetries}`);
            if (retry + 1 < hotspotMaxRetries) {
                setTimeout(() => startHotspotFallbackSafe(retry + 1), 3000);
            } else {
                logger("Hotspot failed after maximum retries. System remains offline.");
            }
            return;
        }

        // Verify hostapd status
        try {
            const hostapdStatus = execSync("systemctl is-active hostapd", { encoding: 'utf8' }).trim();
            if (hostapdStatus !== "active") {
                logger("Hostapd did not reach active state. Retrying fallback.");
                if (retry + 1 < hotspotMaxRetries) {
                    setTimeout(() => startHotspotFallbackSafe(retry + 1), 3000);
                } else {
                    logger("Hostapd failed after maximum retries. System remains offline.");
                }
            } else {
                logger("Hotspot active and hostapd is running.");
                updateNetworkState("hotspot");
            }
        } catch (e) {
            logger("Error checking hostapd status: " + e.message);
            if (retry + 1 < hotspotMaxRetries) {
                setTimeout(() => startHotspotFallbackSafe(retry + 1), 3000);
            } else {
                logger("Could not confirm hostapd status. System remains offline.");
            }
        }
    }

    if (!isWirelessDisabled()) {
        if (checkConcurrentModeSupport()) {
            logger('Fallback: Concurrent AP+STA supported. Starting hotspot.');
            startHotspot(handleHotspotResult);
        } else {
            logger('Fallback: Stopping STA and starting hotspot.');
            stopAP(function () {
                setTimeout(() => {
                    startHotspot(handleHotspotResult);
                }, settleTime);
            });
        }
    } else {
        logger("Fallback: WiFi disabled. No hotspot started.");
    }
}

function stop(callback) {
    stopAP(function() {
        stopHotspot(callback);
    });
}

if ( ! fs.existsSync("/sys/class/net/" + wlan + "/operstate") ) {
    logger("WIRELESS: No wireless interface, exiting");
    process.exit(0);
}


if (process.argv.length < 2) {
    logger("Use: start|stop");
} else {
    var args = process.argv[2];
    logger('WIRELESS DAEMON: ' + args);

    switch (args) {
        case "start":
            logger("Cleaning previous...");
            stopHotspot(function () {
                stopAP(function() {
                    logger("Stopped aP");
                    // Here we set the regdomain if not set
                    detectAndApplyRegdomain(function() {
                        startFlow();
                    });
                })});
            break;
        case "stop":
            stopAP(function() {});
            break;
        case "test":
            wstatus("test");
            break;
    }
}

function wstatus(nstatus) {
    thus.exec("echo " + nstatus + " >/tmp/networkstatus", null);
}

function updateNetworkState(state) {
    wstatus(state);
    refreshNetworkStatusFile();
}

function restartAvahi() {
    logger("Restarting avahi-daemon...");
    thus.exec("/bin/systemctl restart avahi-daemon", function (err, stdout, stderr) {
        if (err) {
            logger("Avahi restart failed: " + err);
        }
    });
}

function logger(msg) {
    if (debug) {
        console.log(msg)
    }
}

function refreshNetworkStatusFile() {
    const fs = require('fs');
    try {
        fs.utimesSync('/tmp/networkstatus', new Date(), new Date());
    } catch (e) {
        logger("Failed to refresh /tmp/networkstatus timestamp: " + e.toString());
    }
}

function getWirelessConfiguration() {
    try {
        var conf = fs.readJsonSync('/data/configuration/system_controller/network/config.json');
        logger('WIRELESS: Loaded configuration');
        logger('WIRELESS CONF: ' + JSON.stringify(conf));
    } catch (e) {
        logger('WIRELESS: First boot');
        var conf = fs.readJsonSync('/volumio/app/plugins/system_controller/network/config.json');
    }
    return conf
}

function isHotspotDisabled() {
    var hotspotConf = getWirelessConfiguration();
    var hotspotDisabled = false;
    if (hotspotConf !== undefined && hotspotConf.enable_hotspot !== undefined && hotspotConf.enable_hotspot.value !== undefined && !hotspotConf.enable_hotspot.value) {
        hotspotDisabled = true;
    }
    return hotspotDisabled
}

function isWirelessDisabled() {
    var wirelessConf = getWirelessConfiguration();
    var wirelessDisabled = false;
    if (wirelessConf !== undefined && wirelessConf.wireless_enabled !== undefined && wirelessConf.wireless_enabled.value !== undefined && !wirelessConf.wireless_enabled.value) {
        wirelessDisabled = true;
    }
    return wirelessDisabled
}

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

function saveWirelessConnectionEstablished() {
    try {
        fs.ensureFileSync(wirelessEstablishedOnceFlagFile)
    } catch (e) {
        logger('Could not save Wireless Connection Established: ' + e);
    }
}

function hasWirelessConnectionBeenEstablishedOnce() {
    var wirelessEstablished = false;
    try {
        if (fs.existsSync(wirelessEstablishedOnceFlagFile)) {
            wirelessEstablished = true;
        }
    } catch(err) {}
    return wirelessEstablished
}

function getWirelessWPADriverString() {
    try {
        var volumioHW = execSync("cat /etc/os-release | grep ^VOLUMIO_HARDWARE | tr -d 'VOLUMIO_HARDWARE=\"'", { uid: 1000, gid: 1000, encoding: 'utf8'}).replace('\n','');
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

function detectAndApplyRegdomain(callback) {
    if (isWirelessDisabled()) {
        return callback();
    }
    var appropriateRegDom = '00';
    try {
        var currentRegDomain = execSync("/usr/bin/sudo /sbin/ifconfig wlan0 up && /usr/bin/sudo /sbin/iw reg get | grep country | cut -f1 -d':'", { uid: 1000, gid: 1000, encoding: 'utf8'}).replace(/country /g, '').replace('\n','');
        var countryCodesInScan = execSync("/usr/bin/sudo /sbin/ifconfig wlan0 up && /usr/bin/sudo /sbin/iw wlan0 scan | grep Country: | cut -f 2", { uid: 1000, gid: 1000, encoding: 'utf8'}).replace(/Country: /g, '').split('\n');
        var appropriateRegDomain = determineMostAppropriateRegdomain(countryCodesInScan);
        logger('CURRENT REG DOMAIN: ' + currentRegDomain)
        logger('APPROPRIATE REG DOMAIN: ' + appropriateRegDomain)
        if (isValidRegDomain(appropriateRegDomain) && appropriateRegDomain !== currentRegDomain) {
            applyNewRegDomain(appropriateRegDomain);
        }
    } catch(e) {
        logger('Failed to determine most appropriate reg domain: ' + e);
    }
    callback();
}

function applyNewRegDomain(newRegDom) {
    logger('SETTING APPROPRIATE REG DOMAIN: ' + newRegDom);

    try {
        execSync("/usr/bin/sudo /sbin/ifconfig wlan0 up && /usr/bin/sudo /sbin/iw reg set " + newRegDom, { uid: 1000, gid: 1000, encoding: 'utf8'});
        //execSync("/usr/bin/sudo /bin/echo 'REGDOMAIN=" + newRegDom + "' > /etc/default/crda", { uid: 1000, gid: 1000, encoding: 'utf8'});
        fs.writeFileSync("/etc/default/crda", "REGDOMAIN=" + newRegDom);
        logger('SUCCESSFULLY SET NEW REGDOMAIN: ' + newRegDom)
    } catch(e) {
        logger('Failed to set new reg domain: ' + e);
    }
}

function isValidRegDomain(regDomain) {
    if (regDomain && regDomain.length === 2) {
        return true;
    } else {
        return false;
    }
}

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

function checkConcurrentModeSupport() {
    try {
        const output = execSync('iw list', { encoding: 'utf8' });
        const comboRegex = /valid interface combinations([\s\S]*?)(?=\n\n)/i;
        const comboBlock = output.match(comboRegex);

        if (!comboBlock || comboBlock.length < 2) {
            logger('WIRELESS: No interface combination block found.');
            return false;
        }

        const comboText = comboBlock[1];

        const hasAP = comboText.includes('AP');
        const hasSTA = comboText.includes('station') || comboText.includes('STA');

        if (hasAP && hasSTA) {
            logger('WIRELESS: Concurrent AP+STA mode supported.');
            return true;
        } else {
            logger('WIRELESS: Concurrent AP+STA mode NOT supported.');
            return false;
        }
    } catch (err) {
        logger('WIRELESS: Failed to determine interface mode support: ' + err);
        return false;
    }
}
