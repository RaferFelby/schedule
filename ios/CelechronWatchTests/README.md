# Apple Watch compatibility tests

Run the suite from the repository root on macOS:

```sh
bash ios/CelechronWatchTests/run_tests.sh
```

The suite intentionally avoids an Xcode test target. It checks only legacy Watch
credential deletion and versioned revocation acknowledgement, which remain necessary
for clearing credentials from users upgrading from older app versions. The retired
campus-card network client and QR payment-code encoder are not included.
