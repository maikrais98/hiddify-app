import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';

class RemainingNotifications extends InAppNotificationController {
  final messages = <String>[];
  @override
  void showSuccessToast(String message, {ToastAction? action}) {
    messages.add(message);
  }

  @override
  void showErrorToast(String message) {
    messages.add(message);
  }
}

class RemainingFiles extends FilePicker {
  final calls = <String>[];
  Uint8List? exported;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    calls.add('pick:${type.name}:${allowedExtensions!.join(',')}:$allowMultiple');
    return null; // Native cancellation: never writes production files.
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    calls.add('save:$fileName:${type.name}:${allowedExtensions!.join(',')}');
    exported = bytes;
    return null;
  }
}
