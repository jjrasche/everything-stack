/// Cargo build script for flutter_rust_bridge integration.
///
/// This tells Cargo when to rebuild based on file changes.
/// Critical for ensuring Rust changes are reflected in Flutter builds.

fn main() {
    // Rebuild if any Rust source file changes
    println!("cargo:rerun-if-changed=src/");

    // Rebuild if Cargo.toml changes (dependency updates)
    println!("cargo:rerun-if-changed=Cargo.toml");

    // Rebuild if Cargo.lock changes (exact version updates)
    println!("cargo:rerun-if-changed=Cargo.lock");
}
