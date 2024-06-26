# fido2luks

This is an extension to initramfs-tools to unlock LUKS-encrypted
volumes at boot time using a FIDO2 token (YubiKey, Nitrokey, ...).

`fido2luks` is designed for scenarios where a FIDO2 token was enrolled
into a LUKS volume using `systemd-cryptenroll --fido2-device` but
systemd itself is not used in the initramfs.

This has successfully been tested with Debian bookworm and trixie (as
of May 2024).

## How to use it

- First of all, a word of warning: this can potentially render your
  system unbootable, so make sure that you have a backup of your files
  or a working initramfs that you can use as a fallback in case things
  go wrong.

- Dependencies: you need `initramfs-tools`, `fido2-tools` and `jq` on
  your system.

- Install `fido2luks`: you can generate a Debian package using the
  scripts that are included for convenience. Simply run `fakeroot
  debian/rules binary` and install the resulting `.deb` file. If you
  prefer not to do that you can run `make install` instead.

- Make sure that the LUKS volume has been set up, e.g.:
  `systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=true --fido2-with-user-presence=true /dev/XXX`.
  You should be able to see the `systemd-fido2` token data if you run
  `cryptsetup luksDump /dev/XXX`.

- Edit `/etc/crypttab` and add `keyscript=/lib/fido2luks/keyscript.sh`
  to the options of the volume that you want to unlock.

- Generate a new initramfs with `update-initramfs -u`.

This should be all. Next time you boot the system `fido2luks` should
detect if your FIDO2 token is inserted and use it to unlock the LUKS
volume. If the token is not detected then it will fall back to using a
regular passphrase as usual.

## How this works

If you are not interested in the technical details you can skip this
section.

When systemd enrolls a FIDO2 token into a LUKS volume it uses an
extension called hmac-secret, supported by many hardware tokens.

In a nutshell, the token calculates an HMAC using a secret that never
leaves the device and a salt provided by the user. The result is sent
back to the user and is used to unlock the LUKS volume.

Since nothing is stored on the hardware token itself the user needs to
provide some data that is kept on the LUKS header:

- A credential ID (previously generated during the enrollment process).
- A _relying party_ ID (`io.systemd.cryptsetup` in this case).
- The aforementioned salt (which should be random and different for
  each LUKS volume).
- Some settings such as whether to require a PIN or presence
  verification (usually physically touching the USB key).

You can look at the scripts under the examples/ directory to see how
to generate your own credentials and secrets. See also the
`fido2-cred(1)` and `fido2-assert(1)` manpages for more details.

## Credits and license

fido2luks was written by Alberto Garcia and is distributed under the
GNU GPL.
