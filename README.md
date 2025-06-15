<!-- markdownlint-disable MD030 -->

# ZFS-Vault

Unlock multiple encrypted [ZFS](https://openzfs.org/) datasets on boot with a
single password.

## Quick summary

This is a minimally-invasive systemd-based solution for unlocking encrypted ZFS
datasets on system startup with single-password unlock and optional automatic
dependent service startup, for example SMB services (Samba). It was mainly
designed for Proxmox Virtual Environment (PVE) but it should work on any system
with ZFS and systemd. This is _not_ intended for high-security environments, but
more for casual or homelab use where you still want encrypted ZFS datasets.

## Why would you want to use this?

If you are not using Full Disk Encryption (FDE) on your system, you may still
have multiple encrypted ZFS datasets that require separate passwords or key
files to unlock, and wish to streamline the process of unlocking them at boot
time. You may also have services like file sharing (Samba) or media servers
(Plex, Jellyfin) that depend on these datasets being unlocked before they can
start. This solution allows you to unlock all of them with a single password.

### Why would you NOT want to use this?

- If you are not using ZFS encryption, or you are using ZFS encryption but
  prefer to enter passwords manually for each dataset.
- If you are using Full Disk Encryption (FDE) on your boot drive and your
  additional ZFS keys are stored there.
- If you are very security conscious. This puts all your metaphorical eggs
  (keys) in one basket (the vault).
  - This is intended more as a convenience for a milder security posture. There
    are some options available here to help mitigate possible attack surface,
    such as closing the vault after the unlock.
  - See [security considerations](#security-considerations) below.
- If there is a catastrophic failure of the vault itself, and you have no other
  backups of the keys, you can potentially lose all of your data. Therefore it
  is recommended to use separate means to backup both your raw ZFS encryption
  keys and the vault pool.

## How does this work exactly?

- Your password-protected "ZFS Vault" dataset stores encryption keys for other
  ZFS pools/datasets, eliminating the need to enter multiple passwords during
  unlock.

  - You run the ZFS Vault unlock script (`/usr/local/bin/zfsvault-unlock`), it
    prompts you for a password then unlocks the other datasets.
  - The vault can be at any (local) location of your choice, such as
    `rpool/vault`, and does not need to be large in size unless you choose to
    store additional files there, which is not recommended.

- **OPTIONAL:** After your system boots, an override on the getty service on the
  first console (TTY1) runs the ZFS Vault unlock script.

  - This script prompts you for the one password to unlock the vault, then
    unlocks the rest of your datasets using key files stored in the vault, then
    (by default) closes the vault.
  - The `zfsvault-unlock` script can also be run manually outside of or instead
    of the boot override.
  - TODO: if you fail the password, currently it waits a few seconds and reboots
    for you to try again. We may refine this behavior, including a chance to
    just cancel the unlock instead of reboot. And password retry.
  - You are not otherwise locked out of the system and can switch to another
    physical or virtual console with this boot override.

- Your additional ZFS datasets (as many as you need) are unlocked using key
  files stored in the vault, then the vault is closed.

  - The configuration file at `/etc/zfsvault.conf` defines which datasets to
    unlock, with what key, and where the vault is located.

- When the unlock completes, a marker file is created at
  `/run/zfsvault-unlocked-marker`. A systemd path unit (`.path`) detects this
  file's creation, which in turn triggers a service
  (`zfsvault-unlocked.service`) to start.

  - You can check this unlock status in your own scripts:

    ```bash
    # Check if ZFS is unlocked
    if [ -f /run/zfsvault-unlocked-marker ]; then
        echo "ZFS is unlocked"
    fi
    ```

- An example LXC container starter service is provided:
  `zfsvault-post-unlocked.service`. This can be customized to your needs to
  start containers for services (SMB, etc.) or other requirements.

  - The example script provided starts two LXC containers (100 and 101) that
    depend on the unlocked datasets.

- If you so choose, other systemd services can be made to depend on
  `zfsvault-unlocked.service` to start only after the ZFS vault has been
  unlocked.

## TODO / missing features

Configuration options are not implemented.

Need "quick start" and finish the actual full installation section. And
uninstall.

## Solution Overview

This solution provides a combination of features that can be used separately or
together:

- **Single password unlock** for multiple encrypted ZFS datasets.
  - Works with encrypted root datasets (entire pools) or individual child
    datasets.
- **Automatic container startup** after ZFS unlock completes
  - Or other services / scripts of your choice.
- **Generic architecture** - easily add/remove datasets and services.
  - Uses systemd path watcher to trigger actions after unlock.
- **Non-invasive** - uses a `systemd` override to non-destructively augment the
  getty service on TTY1. This integration can be cleanly removed without
  altering original system files.
  - Can be easily uninstalled or modified without affecting system integrity.

You can use these features in the following combinations:

- Use all features: password prompt after boot, unlock other ZFS volumes, start
  dependent services.
- Only use the ZFS unlock script manually (no boot or services).
- Trigger the ZFS unlock script manually, and also have dependent services. (But
  not start on boot.)
- Start on boot, unlock ZFS, but no post-unlock services/scripts.

Note that this package does NOT contain cryptography tools, or generate keys for
you, and does not place your datasets into an encrypted state - it simply
provides a convenient means to unlock your existing datasets and trigger
dependent services. You must create your ZFS datasets and encryption keys
yourself, using the standard ZFS tools. See
[security considerations](#security-considerations) below for more details.

The "Vault" itself is a password-protected ZFS dataset, which can be stored on
any accessible local drive. The vault is meant to store ZFS keys only. Although
it is possible to store additional files there, it's recommended not to, and to
allow the default behavior (TODO) of closing the vault when the unlock script is
finished. The vault will take up minimal space on the disk.

### Security considerations

- **Important:** the security of all your datasets unlocked by this tool
  completely depends on the security of the password-protected Vault. All your
  eggs are potentially in one basket.

- Encryption keys for your encrypted ZFS datasets will be created by you. This
  tool does NOT create or manage ZFS keys directly.
- You will place your encryption keys in the vault. Because the ZFS-Vault unlock
  script needs to run as root, your keys should be owned by root and mode `600`
  (only root can read them).
- There is no key rotation or management built into this solution. You must
  manage your keys manually. Changing the vault password does not change the
  underlying keys stored in it. However, you can change the vault password at
  any time.
- Backing up the vault itself, directly or as part of the container disk,
  whether in encrypted or unencrypted state, means that you are backing up the
  keys to your encrypted datasets.
- After unlocking the other datasets, the vault is re-locked unless you disable
  this feature.
- I am not a security researcher or expert. There may be other considerations
  such as keys remaining in kernel memory even after unmount.

Overall, this solution is intended for convenience in homelab or similar
situation where you are trading some defense in depth for ease of use.

### Vault creation best practices

- Use a strong, unique password for the vault dataset.

The vault can be on the same pool as the datasets it unlocks:

**OK:** `tank/vault` unlocks `tank/data`, `tank/storage`

**Also OK:** `rpool/vault` unlocks `tank/data` (different pools)

Just ensure the vault itself is encrypted with a password:

```shell
# Create the vault with strong encryption
zfs create -o encryption=aes-256-gcm \
          -o keylocation=prompt \
          -o keyformat=passphrase \
          -o compression=off \    # Don't compress key material
          -o atime=off \          # Don't leak access patterns
          -o canmount=noauto \    # Require explicit mounting
          tank/vault   # the vault dataset name (adjust as needed, e.g. rpool/vault on Proxmox)

# For generated keys (not the vault itself)
# Use 32 bytes (256 bits) of random data
dd if=/dev/urandom of=dataset.key bs=32 count=1

# Set restrictive permissions
chmod 400 dataset.key
```

### Platform Compatibility

This solution should work on any Linux system with:

- **systemd** (most modern Linux distributions)
- **ZFS** (native or via packages)
- **LXC/containers** (optional)
  - Can use any type of script or service post-unlock, not just LXC containers

The boot integration currently depends on `getty`, which is standard on most
Linux distributions but may not be universal. However, workarounds or
alternatives should be possible in the future.

#### Tested platforms

- Proxmox VE

#### Untested future platforms?

- Ubuntu Server with ZFS
- Debian with ZFS
- TrueNAS SCALE
- Any systemd-based Linux with ZFS support

### Limitations

This package does NOT handle:

- Creating or managing ZFS encryption keys or datasets.
- Remote key servers or distributed key management.
- Network Block Devices, iSCSI volumes, datasets mounted from other machines via
  NFS, etc.
  - This solution is for locally-attached ZFS storage only.
- Full disk encryption. If you are using FDE, you can integrate this with your
  FDE solution, e.g., to require an additional password after initial boot to
  unlock the extra datasets, but this package does not handle or require FDE
  itself.

## Code architecture

The installed file layout looks like this:

```text
/etc/zfsvault/
├── zfsvault.conf                 # Main configuration
├── pools.d/                      # Drop-in configs for each pool
│   ├── storage.conf
│   └── archive.conf
└── post-unlock.d/               # Drop-in scripts to run after unlock
    ├── 10-mount-shares.sh
    └── 20-start-containers.sh

/usr/local/bin/
├── zfsvault-unlock              # Main unlock script
└── zfsvault                     # Optional CLI wrapper

/usr/lib/systemd/system/         # Package-provided units
├── zfsvault-unlock.service
├── zfsvault-unlocked.service
└── zfsvault-unlocked.path

/etc/systemd/system/             # User overrides/customization
└── getty@tty1.service.d/
    └── override.conf
```

The source repository layout looks roughly like:

```text
ZFS-Vault/
├── Makefile
├── README.md
├── debian/                      # For .deb packaging
│   ├── control
│   ├── postinst
│   └── prerm
├── src/
│   ├── bin/
│   │   └── zfsvault-unlock
│   └── systemd/
│       └── *.service
├── config/
│   └── zfsvault.conf.example
└── contrib/                     # Example post-unlock scripts
    ├── lxc-starter.sh
    └── smb-mounts.sh
```

### Config

```conf
# In zfsvault.conf
FEATURES=(
    "boot-unlock"      # Enable getty override
    "auto-mount"       # Auto-mount after unlock
    "post-scripts"     # Run post-unlock.d scripts
)

ZFSVAULT_RETRY_COUNT=3            # Password attempts before reboot
ZFSVAULT_ON_FAIL="reboot"         # Or "shell" for debug
ZFSVAULT_TIMEOUT=30               # Seconds to wait for password
ZFSVAULT_UNMOUNT_AFTER_USE=true   # Unmount vault after loading keys
ZFSVAULT_CLEAR_KEYS=true          # Clear key files from memory/cache
```

The tradeoff of unmounting the vault after use is that if you unmount, you can't
easily add new encrypted datasets later without re-entering the password. But it
does reduce the attack surface.

## Use Cases

### Core Feature: Single-Password ZFS Unlock

- Unlock multiple encrypted ZFS datasets with one password.
- Your "ZFS Vault" dataset stores keys for other ZFS pools / datasets.
- Can be used standalone without boot integration as just a manual unlock
  script.
- Ideal for systems with multiple encrypted datasets that need to be unlocked
  with a single password.

### Optional Feature: Run on startup

- You can either run the unlock script manually at any time, or you can choose
  to run the script automatically on boot.
- This runs as an override on the `getty` console service (on TTY1) to run your
  script immediately after boot. After the unlock completes, the normal login
  prompt appears.
- When at the unlock prompt, you are not locked out of switching to other
  consoles.
- As noted above currently there a dependency on `getty` specifically, but this
  could be adapted to work with other console managers or login methods if
  needed.

### Optional Feature: Service Auto-Start

- Automatically start dependent containers/services after unlock.
- Not limited to containers - can start any systemd services or run any script.
- Works via a systemd path watcher that detects when the ZFS vault is unlocked
  by looking for the `/run/zfsvault-unlocked-marker` file. Works with any
  service dependencies.
- Configurable through simple script editing.
- An example post-unlock script is provided to start LXC containers that depend
  on the unlocked ZFS datasets.

## Prerequisites

- Basic familiarity with ZFS encryption concepts
- Root/sudo access for systemd service configuration
- A ZFS filesystem somewhere. Even if the root filesystem is not ZFS, you can
  create a separate ZFS pool for this purpose. If your root filesystem is ZFS
  and is unencrypted, you can create a separate encrypted ZFS child dataset for
  the vault. This can then be used to store keys for unlocking other datasets on
  other drives / pools.

## How It Works: The Architectural Flow

This solution uses a chain of `systemd` services and units to create a seamless,
interactive boot process. The sequence of events is as follows:

1.  **Boot Interception:** The process begins after the main system services
    have started. A `systemd` override on `getty@tty1.service` prevents the
    normal login prompt from appearing immediately on the first/default console
    (Alt-F1) and instead executes the primary `zfsvault-unlock` script.

2.  **Interactive Unlock:** The `zfsvault-unlock` script takes control of the
    main console (`tty1`) and prompts the user for the single passphrase needed
    to decrypt the primary "vault" dataset.

    - TODO: more about behaviors of the unlock script here. To be refined.
    - For example, if the password is incorrect, it currently waits a few
      seconds and reboots. We may refine this to allow retrying the password or
      canceling the unlock without rebooting.

3.  **Key Loading & Cascade:** Once the vault is unlocked, the script accesses
    the key files stored within it and uses `zfs load-key` to unlock all other
    dependent encrypted datasets in a cascading fashion.

4.  **Success Signal:** Upon successfully unlocking all datasets, the script
    creates an empty "marker file" at `/run/zfsvault-unlocked-marker`. This
    file's existence serves as a system-wide signal that the encrypted storage
    is now available.

    - `/run/` is a temporary filesystem that is cleared on reboot, ensuring the
      marker file is only present when the system is fully unlocked.

5.  **Path Monitoring:** A dedicated `systemd` path unit,
    `zfsvault-unlocked.path`, is active in the background. Its sole job is to
    watch for the creation of the marker file.

6.  **Service Activation:** When the `zfsvault-unlocked.path` unit detects the
    marker file, it immediately triggers the start of its corresponding service,
    `zfsvault-unlocked.service`. This is a simple script (`/bin/true`) that
    serves as a signal to other services that the ZFS vault has been unlocked.

7.  **User-Defined Actions:** The `zfsvault-unlocked` service is a simple
    "signal service". Other services of your choosing can then depend on this
    service to activate only after the ZFS vault has been unlocked.

    - An example service script is provided that starts LXC containers that
      depend on the unlocked ZFS datasets. This service can be customized to
      start any services you need, such as file sharing (Samba), media servers
      (Plex), or other applications that require access to the decrypted
      datasets.

8.  **Console Hand-off:** Finally, after creating the marker file, the initial
    `zfsvault-unlock` script completes its job by handing off control to the
    standard `getty` process, which then presents the normal login prompt on the
    console.

## TODO Future Features

- Clearly separate the core scripts from user defined configuration

  - Location of vault
  - pools to unlock and their path within the vault
  - post-unlock actions.

- Complete packaging, i.e., a `.deb` file?

### Getty dependency

This solution hijacks the getty service on tty1. This is Linux-specific because:

- Not all Unix systems use getty (some BSDs use different console managers)

- Some container systems don't have getty at all

- Embedded systems might have custom console handlers

To make the unlock mechanism independent of getty:

```conf
# CURRENT APPROACH: Override getty@tty1
[Service]
ExecStart=/usr/local/bin/zfsvault-unlock

# NEW zfsvault-unlock.service
[Unit]
Description=ZFS Vault Unlock Prompt
After=basic.target
Before=getty.target  # Run before ANY getty, not just tty1

[Service]
Type=oneshot
ExecStart=/usr/local/bin/zfsvault-unlock
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes

[Install]
WantedBy=multi-user.target
```

Systems without getty can still use it. We're not modifying system services.
It's clearer what the service does. Could potentially be triggered other ways
(SSH, web UI, etc.)

The getty override is simpler and works well for most Linux systems, but the
standalone service is more portable. We could support both methods, but probably
just change to this?

## Architecture diagram

Gemini made this.

```text
 ┌────────────────┐   1. Override   ┌───────────────────┐   2. Prompt   ┌────────┐
 │  getty@tty1    ├───────────────► │ zfsvault-unlock   ├─────────────► │ User   │
 └────────────────┘                 └─────────┬─────────┘               └────────┘
                                              │ 3. Unlock ZFS
                                              │ 4. Create Marker file
                                              ▼
                                 ┌───────────────────────────────┐
                                 │ /run/zfsvault-unlocked-marker │
                                 └────────────┬──────────────────┘
                                              │ 5. Watched By
                                              ▼
                                  ┌─────────────────────────┐   6. Triggers ┌──────────────────────────┐
                                  │ zfsvault-unlocked.path  ├─────────────► │ zfsvault-unlocked.service│
                                  └─────────────────────────┘               └─────────────┬────────────┘
                                                                                          │ 7. Watched By
                                                                                          │   (After=)
                                                                                          ▼
                                                                              ┌────────────────────────┐
                                                                              │ Your Custom Services   │
                                                                              │ (Plex, Samba, LXC, etc)│
                                                                              └────────────────────────┘
```

## TODO: continue here

TODO: below this is unreviewed.

## Installation Instructions

### Step 1: Configure ZFS Unlock Script

Create the ZFS unlock script that handles password prompts and dataset
unlocking:

```bash
# Create the unlock script (adjust paths and pool names for your setup)
cat > /usr/local/bin/zfsvault-unlock << 'EOF'
#!/bin/bash

# Log script start
logger "zfsvault-unlock STARTING ZFS Unlock Script"

# Your ZFS unlock logic here - example:
# Read vault dataset password
read -s -p "Enter vault password: " VAULT_PASS
echo

# Unlock vault dataset containing keys for other pools
echo "$VAULT_PASS" | zfs load-key vault/keys
zfs mount vault/keys

# Load keys for other encrypted datasets
cat /vault/keys/data_key | zfs load-key data
cat /vault/keys/storage_key | zfs load-key storage
cat /vault/keys/archive_key | zfs load-key archive
cat /vault/keys/time-machine_key | zfs load-key time-machine

# Mount all datasets
zfs mount data/user
zfs mount storage/general
zfs mount archive
zfs mount time-machine/backups

logger "zfsvault-unlock ZFS datasets unlocked and mounted"

# Create marker file to signal completion
touch /run/zfsvault-unlocked-marker
systemctl start zfsvault-unlocked.service

logger "zfsvault-unlock signaled completion"

# Hand control back to normal getty process
exec /sbin/agetty -o '-p -- \\u' --noclear tty1 linux
EOF

chmod +x /usr/local/bin/zfsvault-unlock
```

### Step 2: Override getty@tty1 Service

Replace the standard login prompt with your unlock script:

```bash
# Create override directory
mkdir -p /etc/systemd/system/getty@tty1.service.d/

# Create override configuration
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/usr/local/bin/zfsvault-unlock
StandardInput=tty
StandardOutput=tty
EOF

systemctl daemon-reload
```

### Step 3: Create ZFS Unlock Signal Service

This service acts as a completion signal for other services to depend on:

```bash
cat > /etc/systemd/system/zfsvault-unlocked.service << 'EOF'
[Unit]
Description=ZFS Vault Manager - Encrypted Datasets Unlocked Signal

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'test -f /run/zfsvault-unlocked-marker'
RemainAfterExit=yes
EOF
```

### Step 4: Create Container Auto-Start System

Create a path watcher that triggers container startup when ZFS is ready:

```bash
cat > /etc/systemd/system/zfsvault-containers.path << 'EOF'
[Unit]
Description=ZFS Vault Manager - Watch for unlock completion
Documentation=man:systemd.path(5)

[Path]
PathExists=/run/zfsvault-unlocked-marker
Unit=zfsvault-container-starter.service

[Install]
WantedBy=multi-user.target
EOF

# Service that actually starts containers
cat > /etc/systemd/system/zfsvault-container-starter.service << 'EOF'
[Unit]
Description=ZFS Vault Manager - Start dependent containers
After=zfsvault-unlocked.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/zfsvault-start-containers.sh
RemainAfterExit=no
EOF

# Script that starts the containers
cat > /usr/local/bin/zfsvault-start-containers.sh << 'EOF'
#!/bin/bash
logger "zfsvault-container-starter: Starting ZFS-dependent containers"

# Add your container IDs here
pct start 100  # SMB container
pct start 101  # Plex container

# Add more containers as needed:
# pct start 102
# pct start 103

logger "zfsvault-container-starter: Containers started"
EOF

chmod +x /usr/local/bin/zfsvault-start-containers.sh
```

### Step 5: Configure Container Settings

Disable automatic startup for ZFS-dependent containers:

```bash
# Disable onboot for ZFS-dependent containers
pct set 100 --onboot 0  # SMB container
pct set 101 --onboot 0  # Plex container

# Add any additional containers:
# pct set 102 --onboot 0
# pct set 103 --onboot 0
```

### Step 6: Enable and Start Services

```bash
# Enable the path watcher
systemctl enable zfsvault-containers.path

# Reload systemd configuration
systemctl daemon-reload

# Start the path watcher
systemctl start zfsvault-containers.path

# Verify services are configured correctly
systemctl status zfsvault-containers.path
systemctl list-unit-files | grep zfsvault
```

## Configuration Files Summary

The solution creates these files:

- `/usr/local/bin/zfsvault-unlock` - Main unlock script
- `/usr/local/bin/zfsvault-start-containers.sh` - Container startup script
- `/etc/systemd/system/getty@tty1.service.d/override.conf` - Getty override
- `/etc/systemd/system/zfsvault-unlocked.service` - Signal service
- `/etc/systemd/system/zfsvault-containers.path` - Path watcher
- `/etc/systemd/system/zfsvault-container-starter.service` - Container starter

## Usage

1. **Boot the system** - will stop at password prompt instead of login
2. **Enter your vault password** - unlocks all ZFS datasets
3. **Wait for containers** - automatically start after unlock completes
4. **Login normally** - regular getty prompt appears after unlock

## Adding More Containers

To add additional ZFS-dependent containers:

1. Set container to not auto-start: `pct set <ID> --onboot 0`
2. Add to startup script: Edit `/usr/local/bin/zfsvault-start-containers.sh`
3. Add line: `pct start <ID>`

## Troubleshooting

```bash
# Check if path watcher is active
systemctl status zfsvault-containers.path

# Check container startup logs
journalctl -u zfsvault-container-starter.service

# Check if marker file exists after unlock
ls -la /run/zfsvault-unlocked-marker

# Test container startup script manually
/usr/local/bin/zfsvault-start-containers.sh

# View unlock script logs
journalctl | grep "zfsvault-unlock"
```

## Uninstall Instructions

### Step 1: Restore Container Auto-Start

```bash
# Re-enable onboot for containers that should auto-start
pct set 100 --onboot 1
pct set 101 --onboot 1
# Add other containers as needed
```

### Step 2: Remove Custom Services

```bash
# Stop and disable services
systemctl stop zfsvault-containers.path
systemctl disable zfsvault-containers.path
systemctl stop zfsvault-unlocked.service

# Remove service files
rm -f /etc/systemd/system/zfsvault-unlocked.service
rm -f /etc/systemd/system/zfsvault-containers.path
rm -f /etc/systemd/system/zfsvault-container-starter.service

# Remove scripts
rm -f /usr/local/bin/zfsvault-unlock
rm -f /usr/local/bin/zfsvault-start-containers.sh

# Reload systemd
systemctl daemon-reload
```

### Step 3: Restore Original Getty

```bash
# Remove getty override
rm -rf /etc/systemd/system/getty@tty1.service.d/

# Reload systemd
systemctl daemon-reload

# Restart getty to restore normal login
systemctl restart getty@tty1
```

### Step 4: Clean Up Runtime Files

```bash
# Remove any marker files
rm -f /run/zfsvault-unlocked-marker

# Verify clean state
systemctl list-unit-files | grep zfsvault
systemctl status getty@tty1
```

After uninstall, the system will boot normally with standard login prompts and
automatic container startup (if onboot=1).

---

## Notes

- This solution is designed to be non-invasive and easily reversible
- The path watcher approach makes it generic and expandable
- All ZFS unlock logic is contained in the unlock script
- Containers maintain their normal dependencies and configurations
- The solution works with any number of encrypted ZFS pools and containers
