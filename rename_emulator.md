# Rename Emulator Model

The model name shown by `adb devices -l` comes from:

```text
/product/etc/build.prop
ro.product.product.model=<new-name>
```

Start the emulator with writable system support:

```bash
nix develop .#android-a32-33
emulator -writable-system -no-snapshot-load -verbose -show-kernel -gpu host -no-window -avd a33 -port 5554
```

In another terminal:

```bash
adb -s emulator-5554 root
adb -s emulator-5554 remount
adb -s emulator-5554 reboot
adb -s emulator-5554 wait-for-device
adb -s emulator-5554 root
adb -s emulator-5554 remount
adb -s emulator-5554 shell 'mount -o remount,rw /product'
adb -s emulator-5554 shell \
  'sed -i "s/^ro.product.product.model=.*/ro.product.product.model=a33/" /product/etc/build.prop'
adb -s emulator-5554 reboot
```

Verify:

```bash
adb -s emulator-5554 wait-for-device shell \
  'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done; getprop ro.product.model'
adb devices -l
```
