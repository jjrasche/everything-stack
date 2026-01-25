/// Build script for flutter_rust_bridge codegen
///
/// Automatically generates Dart bindings from Rust FFI code.
fn main() {
    // Tell Cargo to rerun if any Rust source files change
    println!("cargo:rerun-if-changed=src/");

    // Run flutter_rust_bridge codegen
    flutter_rust_bridge_codegen::codegen::generate(
        flutter_rust_bridge_codegen::codegen::Config::from_config_file(
            "flutter_rust_bridge.yaml",
        ).unwrap(),
    ).unwrap();
}
