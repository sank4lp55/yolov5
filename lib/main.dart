import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:flutter/material.dart';
import 'dart:async';

late List<CameraDescription> cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MegaView',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurpleAccent),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const YoloVideo(),
    );
  }
}

class YoloVideo extends StatefulWidget {
  const YoloVideo({super.key});

  @override
  State<YoloVideo> createState() => _YoloVideoState();
}

class _YoloVideoState extends State<YoloVideo> {
  late CameraController controller;
  List<Map<String, dynamic>> yoloResults = [];
  CameraImage? cameraImage;
  bool isLoaded = false;
  bool isDetecting = false;

  late FlutterVision vision;
  FlutterTts flutterTts = FlutterTts();
  final StreamController<List<Map<String, dynamic>>> resultStreamController = StreamController.broadcast();

  @override
  void initState() {
    super.initState();
    print("initialized vision");
    vision = FlutterVision();
    initTTS();
    initCamera();
  }

  Future<void> initTTS() async {


    print("init TTTS start");
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(1.0);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
    print("init TTTS end");
  }

  Future<void> speak(String text) async {
    await flutterTts.speak(text);
  }

  Future<void> initCamera() async {
    print("initcamera start");
    controller = CameraController(cameras[0], ResolutionPreset.high, enableAudio: false);
    await controller.initialize();
    await loadYoloModel();
    setState(() {
      isLoaded = true;
    });
    print("initcamera end");
  }

  @override
  void dispose() {
    controller.dispose();
    flutterTts.stop();
    vision.closeYoloModel();
    resultStreamController.close();
    super.dispose();
  }

  Future<void> loadYoloModel() async {
    print("loadyolo model start");
    await vision.loadYoloModel(
      labels: 'assets/labels.txt',
      modelPath: 'assets/yolov5n.tflite',
      modelVersion: "yolov5",
      numThreads: 4, // Reduce to 4 threads for balanced performance
      useGpu: true,
    );
    print("loadyolo model end");
  }

  Future<void> startDetection() async {
    print("Start detection 1");
    setState(() {
      isDetecting = true;
    });
    print("Start detection 2");
    if (!controller.value.isStreamingImages) {
      await controller.startImageStream((image) async {
        if (!isDetecting || cameraImage != null) return; // Skip if already processing
        cameraImage = image;
        processFrame(image);
      });
    }
    print("Start detection 3");
  }

  Future<void> processFrame(CameraImage image) async {
    print("preocess frame start");

    final result = await vision.yoloOnFrame(
      bytesList: image.planes.map((plane) => plane.bytes).toList(),
      imageHeight: image.height,
      imageWidth: image.width,
      iouThreshold: 0.4,
      confThreshold: 0.4,
      classThreshold: 0.5,
    );

    resultStreamController.add(result); // Stream results to the UI
    print(result.length);

    cameraImage = null; // Allow processing of the next frame
    print("preocess frame end");
  }

  Future<void> stopDetection() async {
    setState(() {
      isDetecting = false;
      yoloResults.clear();
    });
    await controller.stopImageStream();
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    if (!isLoaded) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: CameraPreview(controller),
        ),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: resultStreamController.stream,
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
            return Stack(
              children: displayBoxesAroundRecognizedObjects(size, snapshot.data!),
            );
          },
        ),
        Positioned(
          bottom: 75,
          width: MediaQuery.of(context).size.width,
          child: Center(
            child: GestureDetector(
              onTap: isDetecting ? stopDetection : startDetection,
              child: Container(
                height: 80,
                width: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(width: 5, color: Colors.white),
                ),
                child: Icon(
                  isDetecting ? Icons.stop : Icons.play_arrow,
                  color: isDetecting ? Colors.red : Colors.white,
                  size: 50,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> displayBoxesAroundRecognizedObjects(Size screen, List<Map<String, dynamic>> results) {
    double factorX = screen.width / (cameraImage?.height ?? 1);
    double factorY = screen.height / (cameraImage?.width ?? 1);

    return results.map((result) {
      print(result);
      speak(result['tag']);
      return Positioned(
        left: result["box"][0] * factorX,
        top: result["box"][1] * factorY,
        width: (result["box"][2] - result["box"][0]) * factorX,
        height: (result["box"][3] - result["box"][1]) * factorY,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10.0),
            border: Border.all(color: Colors.pink, width: 2.0),
          ),
          child: Text(
            "${result['tag']} ${(result['box'][4] * 100).toStringAsFixed(0)}%",
            style: TextStyle(
              backgroundColor: Colors.green.withOpacity(0.5),
              color: Colors.white,
              fontSize: 16.0,
            ),
          ),
        ),
      );
    }).toList();
  }
}
