# Volumio OS - Hardware Support Request Template

Use this template to request **firmware, driver, or kernel module support** for specific hardware in Volumio OS (Bookworm-based).

This includes:  
- USB Wi-Fi dongles  
- Bluetooth adapters  
- Audio DACs (I2S or USB)  
- Touchscreens or HDMI/DSI displays  
- GPIO HATs or SPI/I2C peripherals  
- Any other hardware requiring kernel or firmware support

## IMPORTANT: READ FIRST

We will only consider requests that contain **enough information to clearly and conclusively identify the hardware**.

If you want your device supported, **you must do the work of identifying it**:

- Do **not** just say "My dongle doesn't work"
- Do **not** link to a forum thread from another project
- Do **not** ask us to guess what you bought

If you cannot provide the technical details needed, your request will be closed without discussion.

## 1. Device Identification

- Device name and type:  
  Example: TP-Link TL-WN823N USB Wi-Fi Adapter

- Vendor or manufacturer:  
  Example: TP-Link Technologies Co., Ltd.

- Hardware revision or PCB version:  
  Example: v3.0, PCB 2023-07

- Interface type (specify one or more):  
  - USB  
  - PCIe  
  - I2C / SPI  
  - GPIO HAT  
  - Other: __________________________

## 2. Identification Details

You must include output from at least one of the following commands:

```shell
lsusb
```

or

```shell
lspci
```

Paste the full line(s) that match the device here:

```
Bus 001 Device 004: ID 0bda:8179 Realtek Semiconductor Corp. RTL8188EUS 802.11n Wireless Network Adapter
```

Additional (if known):

- Vendor ID: `0x0bda`  
- Product ID: `0x8179`

## 3. Technical Documentation

Provide **at least one** of the following:

- Public datasheet (URL):  
  https://example.com/datasheet.pdf

- Product purchase page or listing (URL):  
  https://retailer.com/product/usb-wifi

- Vendor or OEM driver source (URL):  
  https://github.com/xyz/rtl8188eus

- If no public docs exist, attach:
  - Clear photos of the PCB (top and bottom side)
  - Photo of model label or packaging with visible details

## 4. Intended Use Case

Explain what the hardware is expected to do in Volumio OS:

Example:  
"Enable high-gain Wi-Fi streaming for headless Raspberry Pi 4 using USB adapter with RTL8188EUS chipset"

## 5. Confirmation Checklist

- [ ] I have included all required identification information  
- [ ] I have linked a datasheet, product listing, or uploaded PCB photos  
- [ ] I understand that incomplete or vague submissions will be rejected  
- [ ] I want this hardware supported in Bookworm-based Volumio OS

## BAD EXAMPLE (WILL BE IGNORED)

> "My WiFi adapter doesn't work. It's one I got on Amazon. Please add support."

This is unacceptable because:

- No device name, model, or chipset is provided  
- No `lsusb` or `lspci` output  
- No vendor or purchase link  
- No technical documentation


Once complete, post your request either:  
- As a GitHub issue in this repository, or  
- In the Volumio community forum as response to the discussion, or
- A new thread under Help or Development
