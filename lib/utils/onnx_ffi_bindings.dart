import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

// Define a class to hold the ONNX Runtime C API bindings.
class OnnxFfiBindings {
  static final OnnxFfiBindings _instance = OnnxFfiBindings._internal();
  late final ffi.DynamicLibrary _lib;

  factory OnnxFfiBindings() {
    return _instance;
  }

  OnnxFfiBindings._internal() {
    _lib = _openLibrary();
  }

  ffi.DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      // For Android, we load the library by its full name.
      // The system linker will find it in the jniLibs directory.
      return ffi.DynamicLibrary.open('libonnxruntime.so');
    } else if (Platform.isIOS) {
      // For iOS, you might need to load it differently, often it's statically linked
      // or available via a framework.
      // This is a placeholder.
      return ffi.DynamicLibrary.process();
    } else {
      // Placeholder for other platforms (Linux, Windows, macOS)
      // You would need to adjust the library name/path accordingly.
      throw UnsupportedError('Unsupported platform: \\${Platform.operatingSystem}');
    }
  }

  // We will add function lookups here later.
  // For example:
  // late final GetApiBase_Type = _lib.lookupFunction<
  //     ffi.Pointer<OrtApiBase> Function(),
  //     GetApiBase_Dart_Type>('GetApiBase');

  late final GetApiBase =
      _lib.lookupFunction<GetApiBase_native_t, GetApiBase_dart_t>('OrtGetApiBase');
}

// --- C-style type definitions for FFI ---

// Add ORT_API_VERSION
const ORT_API_VERSION = 17;

/// An enum for the ONNX Runtime logging level.
enum OrtLoggingLevel {
  verbose,
  info,
  warning,
  error,
  fatal,
}

// Opaque structs
final class OrtEnv extends ffi.Opaque {}
final class OrtStatus extends ffi.Opaque {}
final class OrtSessionOptions extends ffi.Opaque {}
final class OrtSession extends ffi.Opaque {}
final class OrtValue extends ffi.Opaque {}
final class OrtAllocator extends ffi.Opaque {}
final class OrtMemoryInfo extends ffi.Opaque {}
final class OrtApi extends ffi.Opaque {}

/// Enum for ONNX Tensor Data Types
enum ONNXTensorElementDataType {
  undefined,
  float,
  uint8,
  int8,
  uint16,
  int16,
  int32,
  int64,
  string,
  bool,
  float16,
  double,
  uint32,
  uint64,
  complex64,
  complex128,
  bfloat16,
}

/// Enum for Allocator Type
enum OrtAllocatorType {
  invalid,
  device,
  arena,
}

/// Enum for Mem Type
enum OrtMemType {
  cpuInput,
  cpuOutput,
  default_,
}

final class OrtApiBase extends ffi.Struct {
  external ffi.Pointer<ffi.NativeFunction<GetApi_native_t>> GetApi;
  external ffi.Pointer<ffi.NativeFunction<GetVersionString_native_t>> GetVersionString;
}

typedef GetApi_native_t = ffi.Pointer<OrtApi> Function(ffi.Uint32);
typedef GetApi_dart_t = ffi.Pointer<OrtApi> Function(int);

typedef GetVersionString_native_t = ffi.Pointer<Utf8> Function();
typedef GetVersionString_dart_t = ffi.Pointer<Utf8> Function();


/// The C-side struct definition for the OrtApi.
/// This contains pointers to all the C functions.
final class OrtApiStruct extends ffi.Struct {
  external ffi.Pointer<ffi.NativeFunction<CreateEnv_native_t>> createEnv;
  external ffi.Pointer<ffi.NativeFunction<CreateSessionOptions_native_t>> createSessionOptions;
  external ffi.Pointer<ffi.NativeFunction<SetIntraOpNumThreads_native_t>> setIntraOpNumThreads;
  external ffi.Pointer<ffi.NativeFunction<SetInterOpNumThreads_native_t>> setInterOpNumThreads;
  external ffi.Pointer<ffi.NativeFunction<CreateSessionFromArray_native_t>> createSessionFromArray;

  external ffi.Pointer<ffi.NativeFunction<GetErrorMessage_native_t>> getErrorMessage;
  external ffi.Pointer<ffi.NativeFunction<ReleaseStatus_native_t>> releaseStatus;
  external ffi.Pointer<ffi.NativeFunction<ReleaseEnv_native_t>> releaseEnv;
  external ffi.Pointer<ffi.NativeFunction<ReleaseSessionOptions_native_t>> releaseSessionOptions;
  external ffi.Pointer<ffi.NativeFunction<ReleaseSession_native_t>> releaseSession;

  // Tensor/Value functions
  external ffi.Pointer<ffi.NativeFunction<CreateTensorWithDataAsOrtValue_native_t>> createTensorWithDataAsOrtValue;
  external ffi.Pointer<ffi.NativeFunction<GetTensorMutableData_native_t>> getTensorMutableData;
  external ffi.Pointer<ffi.NativeFunction<ReleaseValue_native_t>> releaseValue;

  // Run functions
  external ffi.Pointer<ffi.NativeFunction<Run_native_t>> run;

  // Allocator functions
  external ffi.Pointer<ffi.NativeFunction<GetAllocatorWithDefaultOptions_native_t>> getAllocatorWithDefaultOptions;
  external ffi.Pointer<ffi.NativeFunction<ReleaseAllocator_native_t>> releaseAllocator;

  // Memory Info
  external ffi.Pointer<ffi.NativeFunction<CreateCpuMemoryInfo_native_t>> createCpuMemoryInfo;
  external ffi.Pointer<ffi.NativeFunction<ReleaseMemoryInfo_native_t>> releaseMemoryInfo;
}

// Function pointer types
typedef GetApiBase_native_t = ffi.Pointer<OrtApiBase> Function();
typedef GetApiBase_dart_t = ffi.Pointer<OrtApiBase> Function();

// CreateEnv
typedef CreateEnv_native_t = ffi.Pointer<OrtStatus> Function(
    ffi.Pointer<OrtEnv>, ffi.Int32, ffi.Pointer<Utf8>, ffi.Pointer<ffi.Pointer<OrtEnv>>);
typedef CreateEnv_dart_t = ffi.Pointer<OrtStatus> Function(
    ffi.Pointer<OrtEnv>, int, ffi.Pointer<Utf8>, ffi.Pointer<ffi.Pointer<OrtEnv>>);

// CreateSessionOptions
typedef CreateSessionOptions_native_t = ffi.Pointer<OrtStatus> Function(
    ffi.Pointer<ffi.Pointer<OrtSessionOptions>>);
typedef CreateSessionOptions_dart_t = ffi.Pointer<OrtStatus> Function(
    ffi.Pointer<ffi.Pointer<OrtSessionOptions>>);

// SetIntraOpNumThreads
typedef SetIntraOpNumThreads_native_t = ffi.Pointer<OrtStatus> Function(ffi.Pointer<OrtSessionOptions>, ffi.Int);
typedef SetIntraOpNumThreads_dart_t = ffi.Pointer<OrtStatus> Function(ffi.Pointer<OrtSessionOptions>, int);

// SetInterOpNumThreads
typedef SetInterOpNumThreads_native_t = ffi.Pointer<OrtStatus> Function(ffi.Pointer<OrtSessionOptions>, ffi.Int);
typedef SetInterOpNumThreads_dart_t = ffi.Pointer<OrtStatus> Function(ffi.Pointer<OrtSessionOptions>, int);

// CreateSessionFromArray
typedef CreateSessionFromArray_native_t = ffi.Pointer<OrtStatus> Function(
    ffi.Pointer<OrtEnv>, ffi.Pointer<ffi.Void>, ffi.Size, ffi.Pointer<OrtSessionOptions>, ffi.Pointer<ffi.Pointer<OrtSession>>);
typedef CreateSessionFromArray_dart_t = ffi.Pointer<OrtStatus> Function(
    ffi.Pointer<OrtEnv>, ffi.Pointer<ffi.Void>, int, ffi.Pointer<OrtSessionOptions>, ffi.Pointer<ffi.Pointer<OrtSession>>);

// GetErrorMessage
typedef GetErrorMessage_native_t = ffi.Pointer<Utf8> Function(ffi.Pointer<OrtStatus>);
typedef GetErrorMessage_dart_t = ffi.Pointer<Utf8> Function(ffi.Pointer<OrtStatus>);

// ReleaseStatus
typedef ReleaseStatus_native_t = ffi.Void Function(ffi.Pointer<OrtStatus>);
typedef ReleaseStatus_dart_t = void Function(ffi.Pointer<OrtStatus>);

// ReleaseEnv
typedef ReleaseEnv_native_t = ffi.Void Function(ffi.Pointer<OrtEnv>);
typedef ReleaseEnv_dart_t = void Function(ffi.Pointer<OrtEnv>);

// ReleaseSessionOptions
typedef ReleaseSessionOptions_native_t = ffi.Void Function(ffi.Pointer<OrtSessionOptions>);
typedef ReleaseSessionOptions_dart_t = void Function(ffi.Pointer<OrtSessionOptions>);

// ReleaseSession
typedef ReleaseSession_native_t = ffi.Void Function(ffi.Pointer<OrtSession>);
typedef ReleaseSession_dart_t = void Function(ffi.Pointer<OrtSession>);

// CreateTensorWithDataAsOrtValue
typedef CreateTensorWithDataAsOrtValue_native_t = ffi.Pointer<OrtStatus> Function(
    ffi.Pointer<OrtMemoryInfo>, ffi.Pointer<ffi.Void>, ffi.Size, ffi.Pointer<ffi.Int64>, ffi.Size, ffi.Int32, ffi.Pointer<ffi.Pointer<OrtValue>>);
typedef CreateTensorWithDataAsOrtValue_dart_t = ffi.Pointer<OrtStatus> Function(
    ffi.Pointer<OrtMemoryInfo>, ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Int64>, int, int, ffi.Pointer<ffi.Pointer<OrtValue>>);

// GetTensorMutableData
typedef GetTensorMutableData_native_t = ffi.Pointer<OrtStatus> Function(
    ffi.Pointer<OrtValue>, ffi.Pointer<ffi.Pointer<ffi.Void>>);
typedef GetTensorMutableData_dart_t = ffi.Pointer<OrtStatus> Function(
    ffi.Pointer<OrtValue>, ffi.Pointer<ffi.Pointer<ffi.Void>>);

// ReleaseValue
typedef ReleaseValue_native_t = ffi.Void Function(ffi.Pointer<OrtValue>);
typedef ReleaseValue_dart_t = void Function(ffi.Pointer<OrtValue>);

// Run
typedef Run_native_t = ffi.Pointer<OrtStatus> Function(
    ffi.Pointer<OrtSession>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<Utf8>>, ffi.Pointer<ffi.Pointer<OrtValue>>, ffi.Size, ffi.Pointer<ffi.Pointer<Utf8>>, ffi.Size, ffi.Pointer<ffi.Pointer<OrtValue>>);
typedef Run_dart_t = ffi.Pointer<OrtStatus> Function(
    ffi.Pointer<OrtSession>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<Utf8>>, ffi.Pointer<ffi.Pointer<OrtValue>>, int, ffi.Pointer<ffi.Pointer<Utf8>>, int, ffi.Pointer<ffi.Pointer<OrtValue>>);

// GetAllocatorWithDefaultOptions
typedef GetAllocatorWithDefaultOptions_native_t = ffi.Pointer<OrtStatus> Function(ffi.Pointer<ffi.Pointer<OrtAllocator>>);
typedef GetAllocatorWithDefaultOptions_dart_t = ffi.Pointer<OrtStatus> Function(ffi.Pointer<ffi.Pointer<OrtAllocator>>);

// ReleaseAllocator
typedef ReleaseAllocator_native_t = ffi.Void Function(ffi.Pointer<OrtAllocator>);
typedef ReleaseAllocator_dart_t = void Function(ffi.Pointer<OrtAllocator>);

// CreateCpuMemoryInfo
typedef CreateCpuMemoryInfo_native_t = ffi.Pointer<OrtStatus> Function(ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Pointer<OrtMemoryInfo>>);
typedef CreateCpuMemoryInfo_dart_t = ffi.Pointer<OrtStatus> Function(int, int, ffi.Pointer<ffi.Pointer<OrtMemoryInfo>>);

// ReleaseMemoryInfo
typedef ReleaseMemoryInfo_native_t = ffi.Void Function(ffi.Pointer<OrtMemoryInfo>);
typedef ReleaseMemoryInfo_dart_t = void Function(ffi.Pointer<OrtMemoryInfo>);


// Global instance of the bindings.
final onnxBindings = OnnxFfiBindings();
