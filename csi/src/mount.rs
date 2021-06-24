//! Utility functions for mounting and unmounting filesystems.

use std::io::Error;

use proc_mounts::MountIter;
use sys_mount::{unmount, FilesystemType, Mount, MountFlags, UnmountFlags};

// Simple trait for checking if the readonly (ro) option
// is present in a "list" of options, while allowing for
// flexibility as to the type of "list".
pub(super) trait ReadOnly {
    fn readonly(&self) -> bool;
}

impl ReadOnly for Vec<String> {
    fn readonly(&self) -> bool {
        self.iter().any(|entry| entry == "ro")
    }
}

impl ReadOnly for &str {
    fn readonly(&self) -> bool {
        self.split(',').any(|entry| entry == "ro")
    }
}

// Information about a mounted filesystem.
#[derive(Debug)]
pub struct MountInfo {
    pub source: String,
    pub dest: String,
    pub fstype: String,
    pub options: Vec<String>,
}

impl From<proc_mounts::MountInfo> for MountInfo {
    fn from(mount: proc_mounts::MountInfo) -> MountInfo {
        MountInfo {
            source: mount.source.to_string_lossy().to_string(),
            dest: mount.dest.to_string_lossy().to_string(),
            fstype: mount.fstype,
            options: mount.options,
        }
    }
}

/// Return mountinfo matching source and/or destination.
pub fn find_mount(
    source: Option<&str>,
    target: Option<&str>,
) -> Option<MountInfo> {
    let mut found: Option<proc_mounts::MountInfo> = None;

    for mount in MountIter::new().unwrap().flatten() {
        if let Some(value) = source {
            if mount.source.to_string_lossy() == value {
                if let Some(value) = target {
                    if mount.dest.to_string_lossy() == value {
                        found = Some(mount);
                    }
                    continue;
                }
                found = Some(mount);
            }
            continue;
        }
        if let Some(value) = target {
            if mount.dest.to_string_lossy() == value {
                found = Some(mount);
            }
        }
    }

    found.map(MountInfo::from)
}

/// Return supported filesystems.
pub fn probe_filesystems() -> Vec<String> {
    vec![String::from("xfs"), String::from("ext4")]
}

// Utility function to transform a vector of options
// to the format required by sys_mount::Mount::new()
fn parse(options: &[String]) -> (bool, String) {
    let mut list: Vec<&str> = Vec::new();
    let mut readonly: bool = false;

    for entry in options {
        if entry == "ro" {
            readonly = true;
            continue;
        }

        if entry == "rw" {
            continue;
        }

        list.push(entry);
    }

    (readonly, list.join(","))
}

// Utility function to wrap a string in an Option.
// Note that, in particular, the empty string is mapped to None.
fn option(value: &str) -> Option<&str> {
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

// Utility function used for displaying a list of options.
fn show(options: &[String]) -> String {
    let list: Vec<String> = options
        .iter()
        .cloned()
        .filter(|value| value != "rw")
        .collect();

    if list.is_empty() {
        return String::from("none");
    }

    list.join(",")
}

/// Mount a device to a directory (mountpoint)
pub fn filesystem_mount(
    device: &str,
    target: &str,
    fstype: &str,
    options: &[String],
) -> Result<Mount, Error> {
    let mut flags = MountFlags::empty();

    let (readonly, value) = parse(options);

    if readonly {
        flags.insert(MountFlags::RDONLY);
    }

    let mount = Mount::new(
        device,
        target,
        FilesystemType::Manual(fstype),
        flags,
        option(&value),
    )?;

    debug!(
        "Filesystem ({}) on device {} mounted onto target {} (options: {})",
        fstype,
        device,
        target,
        show(options)
    );

    Ok(mount)
}

/// Unmount a device from a directory (mountpoint)
/// Should not be used for removing bind mounts.
pub fn filesystem_unmount(target: &str) -> Result<(), Error> {
    let mut flags = UnmountFlags::empty();

    flags.insert(UnmountFlags::DETACH);

    unmount(target, flags)?;

    debug!("Target {} unmounted", target);

    Ok(())
}

/// Mount a block device
pub fn blockdevice_mount(
    source: &str,
    target: &str,
    readonly: bool,
) -> Result<Mount, Error> {
    debug!("Mounting {} ...", source);

    let mut flags = MountFlags::empty();
    flags.insert(MountFlags::BIND);

    let mount = Mount::new(
        source,
        target,
        FilesystemType::Manual("none"),
        flags,
        None,
    )?;
    info!("Block device {} mounted to {}", source, target,);

    if readonly {
        flags.insert(MountFlags::REMOUNT);
        flags.insert(MountFlags::RDONLY);

        let mount =
            Mount::new("", target, FilesystemType::Manual(""), flags, None)?;
        info!("Remounted block device {} (readonly) to {}", source, target,);
        return Ok(mount);
    }

    Ok(mount)
}

/// Unmount a block device.
pub fn blockdevice_unmount(target: &str) -> Result<(), Error> {
    let flags = UnmountFlags::empty();

    debug!("Unmounting block device {} (flags={:?}) ...", target, flags);

    unmount(&target, flags)?;
    info!("block device at {} has been unmounted", target);
    Ok(())
}
