// Native assets build hook for Rust FFI
// This compiles the Rust library for the target platform during Flutter builds
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async {
  await build(
    args,
    (input, output) async {
      final builder = RustBuilder(
        assetName: 'everything_stack_native',
        cratePath: 'rust',
        buildMode: BuildMode.release,
      );
      await builder.run(input: input, output: output, logger: Logger('RustBuilder'));
    },
  );
}
