import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as imglib;
import 'package:path_provider/path_provider.dart';

import 'camera_view.dart';
import 'painters/face_detector_painter.dart';

class FaceDetectorView extends StatefulWidget {
  @override
  State<FaceDetectorView> createState() => _FaceDetectorViewState();
}

class _FaceDetectorViewState extends State<FaceDetectorView> {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
    ),
  );
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  String? _text;
  String? _tempFilePath;
  double _prevX = 0.0;
  double _prevY = 0.0;

  @override
  void dispose() {
    _canProcess = false;
    _faceDetector.close();
    super.dispose();
  }

  int getRGBAFromYUV(int yValue, int uValue, int vValue) {
    //print('$yValue, $uValue, $vValue');
    const int shift = (0xFF << 24); // | 0xFF;
    final r = (yValue + 1.370705 * vValue).round();
    final g = (yValue - (0.698001 * vValue) - (0.337633 * uValue)).round();
    final b = (yValue + 1.732446 * uValue).round();
    //final bgraValue = shift | (b << 24) | (g << 16) | r << 8;
    final rgbaValue = shift | (b << 16) | (g << 8) | r << 0;
    return rgbaValue;
  }

  @override
  Widget build(BuildContext context) {
    return CameraView(
      title: 'Face Detector',
      customPaint: _customPaint,
      text: _text,
      onImage: (inputImage) {
        processImage(inputImage);
      },
      initialDirection: CameraLensDirection.front,
    );
  }

  imglib.Image _convertYUV420(int width, int height, Uint8List image,
      List<InputImagePlaneMetadata> planes, InputImageRotation rotation) {
    var img = imglib.Image(width, height); // Create Image buffer

    for (int x = 0; x < width; x++) {
      for (int y = 0; y < height; y++) {
        final yValue = planes[0].data![y * width + x];
        final imgIndex = y * width + x;
        final uvIndex = ((y / 2) * (width / 2) + (x / 2)).round();
        final uValue = (planes[1].data![uvIndex] - 128) * 1;
        final vValue = (planes[2].data![uvIndex] - 128) * 1;
        img.data[imgIndex] = getRGBAFromYUV(yValue, uValue, vValue);
      }
    }
    if (rotation != InputImageRotation.rotation0deg) {
      switch (rotation) {
        case InputImageRotation.rotation90deg:
          img = imglib.copyRotate(img, 90);
          break;
        case InputImageRotation.rotation180deg:
          img = imglib.copyRotate(img, 180);
          break;
        case InputImageRotation.rotation270deg:
          img = imglib.copyRotate(img, 270);
          break;
        default:
          break;
      }
    }
    return img;
  }

  imglib.Image _convertYUV420Greyscale(
      int width, int height, Uint8List image, InputImageRotation rotation) {
    var img = imglib.Image(width, height); // Create Image buffer

    //final Plane plane = image.planes[0];
    const int shift = (0xFF << 24);

    // Fill image buffer with plane[0] from YUV420_888
    for (int x = 0; x < width; x++) {
      for (int planeOffset = 0;
          planeOffset < height * width;
          planeOffset += width) {
        final pixelColor = image[planeOffset + x];
        // color: 0x FF  FF  FF  FF
        //           A   B   G   R
        // Calculate pixel color

        final newVal =
            shift | (pixelColor << 16) | (pixelColor << 8) | pixelColor;

        img.data[planeOffset + x] = newVal;
      }
    }

    if (rotation != InputImageRotation.rotation0deg) {
      switch (rotation) {
        case InputImageRotation.rotation90deg:
          img = imglib.copyRotate(img, 90);
          break;
        case InputImageRotation.rotation180deg:
          img = imglib.copyRotate(img, 180);
          break;
        case InputImageRotation.rotation270deg:
          img = imglib.copyRotate(img, 270);
          break;
        default:
          break;
      }
    }
    return img;
  }

  Future<void> processImage(InputImage inputImage) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;
    setState(() {
      _text = '';
    });
    final faces = await _faceDetector.processImage(inputImage);
    if (inputImage.inputImageData?.size != null &&
        inputImage.inputImageData?.imageRotation != null) {
      final painter = FaceDetectorPainter(
          faces,
          inputImage.inputImageData!.size,
          inputImage.inputImageData!.imageRotation);
      _customPaint = CustomPaint(
          size: Size(inputImage.inputImageData!.size.width,
              inputImage.inputImageData!.size.height),
          painter: painter);

      String text = 'Faces found: ${faces.length}\n\n';

      for (final face in faces) {
        final Rect boundingBox = face.boundingBox;

        final double? rotX =
            face.headEulerAngleX; // Head is tilted up and down rotX degrees
        final double? rotY =
            face.headEulerAngleY; // Head is rotated to the right rotY degrees
        // final double? rotZ = face.headEulerAngleZ; // Head is tilted sideways rotZ degrees
        print('$boundingBox, $rotX, $rotY');
        if (rotX != null &&
            rotY != null &&
            rotX.abs() < 10.0 &&
            rotY.abs() > 20 &&
            ((_prevX - rotX.abs()).abs() + (_prevY - rotY.abs()).abs()) < 1) {
          _canProcess = false;

          imglib.Image img;

          // save image
          print(inputImage.inputImageData!.inputImageFormat);
          imglib.Format imgFormat = imglib.Format.bgra; // iOS default
          switch (inputImage.inputImageData!.inputImageFormat) {
            case InputImageFormat.yuv_420_888: // Pixel
              img = _convertYUV420(
                  //img = _convertYUV420Greyscale(
                  inputImage.inputImageData!.size.width.toInt(),
                  inputImage.inputImageData!.size.height.toInt(),
                  inputImage.bytes!,
                  inputImage.inputImageData!.planeData!,
                  inputImage.inputImageData!.imageRotation);
              break;
            default:
              imgFormat = imglib.Format.bgra;
              img = imglib.Image.fromBytes(
                  inputImage.inputImageData!.size.width.toInt(),
                  inputImage.inputImageData!.size.height.toInt(),
                  inputImage.bytes!,
                  format: imgFormat);
              break;
          }

          final imglib.PngEncoder pngEncoder = imglib.PngEncoder();
          final List<int> png = pngEncoder.encodeImage(img);

          final Directory tempDir = await getApplicationDocumentsDirectory();
          setState(() {
            final nowString = DateTime.now().toString();
            _tempFilePath = '${tempDir.path}/$nowString.png';
          });

          File(_tempFilePath!).writeAsBytes(png);

          //カメラのシャッターを切って、そのimageを別のviewへnavigateする
          Navigator.of(context)
              .push(MaterialPageRoute<bool>(builder: (BuildContext context) {
            return StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
              return Scaffold(
                appBar: AppBar(
                  title: Text('Captured Image'),
                ),
                body: WillPopScope(
                  onWillPop: () async {
                    Navigator.pop(context, true);
                    _canProcess = true;
                    await File(_tempFilePath!).delete();
                    return false;
                  },
                  child: Image.file(File(_tempFilePath!)),
                ),
              );
            });
          }));
          //_canProcess = false;
        } else {
          _prevX = rotX != null ? rotX.abs() : 0;
          _prevY = rotY != null ? rotY.abs() : 0;
        }

        text += 'face: ${face.boundingBox}\n\n';
      }
      print(text);
    }
    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }
}
