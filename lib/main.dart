import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as Path;
import 'package:flutter/material.dart';
import 'package:file_chooser/file_chooser.dart' as FileChooser;
import 'package:menubar/menubar.dart' as Menubar;
import 'package:window_size/window_size.dart' as WindowSize;
import 'package:lzma/lzma.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drone Thumbnail Editor',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
      ),
      home: MyHomePage(title: 'Drone Thumbnail Editor'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key) {
    WindowSize.setWindowTitle("Drone Thumbnail Editor");
  }
  
  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

/**
 * I don't know if it's possible to read the Windows registry via Flutter (yet)
 */
var DIRECTORY_C = Directory("C:\\Program Files (x86)\\Steam\\steamapps\\common\\D.R.O.N.E. The Game\\branches\\stable\\D.R.O.N.E. The Game_Data\\Drones");
var DIRECTORY_C_64 = Directory("C:\\Program Files\\Steam\\steamapps\\common\\D.R.O.N.E. The Game\\branches\\stable\\D.R.O.N.E. The Game_Data\\Drones");
var DIRECTORY_D = Directory("D:\\Program Files (x86)\\Steam\\steamapps\\common\\D.R.O.N.E. The Game\\branches\\stable\\D.R.O.N.E. The Game_Data\\Drones");
var DIRECTORY_D_64 = Directory("D:\\Program Files\\Steam\\steamapps\\common\\D.R.O.N.E. The Game\\branches\\stable\\D.R.O.N.E. The Game_Data\\Drones");


class EmbeddedThumbnail {
  //Thumbnail index should be way before, but just to be sure...
  static const int MAX_SCAN_SIZE = 10000;
  final int index, size, endIndex;
  final ImgFormat format;

  EmbeddedThumbnail._(this.format, this.index, this.size) : endIndex = index + size;

  static EmbeddedThumbnail _getAt(Uint8List data, int index) {
    index = max(index, 4);
    var format = data.imageFormatAtIndex(index);
    int size = (format != null) ? Int8List.fromList([data[index-1], data[index-2], data[index-3], data[index-4]]).buffer.asByteData().getInt32(0) : -1;
    return (size >= 0 && size <= data.length - index) ? EmbeddedThumbnail._(format, index, size) : null;
  }

  static EmbeddedThumbnail fromLevel(Uint8List data) {
    int startIndex;
    if (data.length <= 12 || (startIndex = data[4].toInt() + 12) >= data.length || startIndex < 12) return null;
    for (int index = startIndex; index < min(MAX_SCAN_SIZE, data.length); index++) {
      var thumbnail = _getAt(data, index);
      if (thumbnail != null) return thumbnail;
    }
    return null;
  }
  static EmbeddedThumbnail fromDrone(Uint8List data) {
    if (data.length < 8) return null;
    return _getAt(data, 8);
  }
}

enum GameFileType {
  DRONE, LEVEL
}
extension on GameFileType {
  static final Map<GameFileType, String> fileTypeLabels = HashMap.fromEntries([
    MapEntry(GameFileType.DRONE, "DRONE drone"),
    MapEntry(GameFileType.LEVEL, "DRONE level")
  ]);
  FileChooser.FileTypeFilterGroup get fileTypeGroup {
    return FileChooser.FileTypeFilterGroup(label: fileTypeLabels[this] ?? "Unknown", fileExtensions: [this?.toString()?.split('.')?.elementAt(1)?.toLowerCase() ?? "*"]);
  }

  EmbeddedThumbnail Function(Uint8List data) get getEmbeddedThumbnail {switch(this) {
    case GameFileType.DRONE: return EmbeddedThumbnail.fromDrone;
    case GameFileType.LEVEL: return EmbeddedThumbnail.fromLevel;
    default: return (data) => null;
  }}

  Uint8List decode(Uint8List data) {try{switch(this) {
    case GameFileType.LEVEL: return Uint8List.fromList(lzma.decode(data));
    default: return data;
  }}catch(e) {return Uint8List.fromList([]);}}

  Uint8List encode(Uint8List data) {switch(this) {
    case GameFileType.LEVEL: return Uint8List.fromList(lzma.encode(data));
    default: return data;
  }}
}
var gameFileTypeGroup = FileChooser.FileTypeFilterGroup(label: "DRONE data file", fileExtensions: GameFileType.values.expand((e) => e.fileTypeGroup.fileExtensions).toList());
GameFileType gameFileTypeFromExtension(String value){
  if (value.startsWith("\.")) value = value.substring(1);
  return GameFileType.values.firstWhere((e)=> e.toString().split('.')[1].toUpperCase() == value.toUpperCase());
}

enum ImgFormat {
  JPEG, PNG, GIF, BMP, WEBP
}
FileChooser.FileTypeFilterGroup combineImageFileTypeGroup(String label, List<ImgFormat> formats) {
  return FileChooser.FileTypeFilterGroup(label: label, fileExtensions: formats.expand((e) => e.fileTypeGroup.fileExtensions).toList());
}
var supportedImageFileTypeGroup = combineImageFileTypeGroup("Supported image formats", [ImgFormat.PNG, ImgFormat.JPEG]);


extension on Int8List {
  Uint8List get unsigned {return this.buffer.asUint8List();} 
}
extension on ImgFormat {
  static final Map<ImgFormat, Uint8List> signatures = HashMap.fromEntries([
    MapEntry(ImgFormat.JPEG, Int8List.fromList([0xFF, 0xD8, 0xFF]).unsigned),
    MapEntry(ImgFormat.PNG, Int8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).unsigned),
    MapEntry(ImgFormat.GIF, Int8List.fromList([0x47, 0x49, 0x46]).unsigned),
    MapEntry(ImgFormat.BMP, Int8List.fromList([0x42, 0x4D]).unsigned),
    MapEntry(ImgFormat.WEBP, Int8List.fromList([0x52, 0x49, 0x46, 0x46]).unsigned)
  ]);
  static final Map<ImgFormat, FileChooser.FileTypeFilterGroup> fileTypeGroups = HashMap.fromEntries([
    MapEntry(ImgFormat.JPEG, FileChooser.FileTypeFilterGroup(label: "JPEG", fileExtensions: ["jpg", "jpeg", "jpe", "jfif", "exif"])),
    MapEntry(ImgFormat.PNG, FileChooser.FileTypeFilterGroup(label: "PNG", fileExtensions: ["png"])),
    MapEntry(ImgFormat.GIF, FileChooser.FileTypeFilterGroup(label: "GIF", fileExtensions: ["gif"])),
    MapEntry(ImgFormat.BMP, FileChooser.FileTypeFilterGroup(label: "BMP", fileExtensions: ["bmp", "dib", "rle"])),
    MapEntry(ImgFormat.WEBP, FileChooser.FileTypeFilterGroup(label: "WebP", fileExtensions: ["webp"]))
  ]);
  Uint8List get signature {
    return signatures[this];
  }
  FileChooser.FileTypeFilterGroup get fileTypeGroup {
    return (this != null) ? fileTypeGroups[this] : FileChooser.FileTypeFilterGroup(label: "Unknown", fileExtensions: ["*"]);
  }
  bool checkHeaderSignature(Uint8List fileData, [int index = 0]) {
    var signature = this.signature;
    if (this == null || (fileData.length-index) < signature.length) return false;
    for(var i=0; i< signature.length; i++) if (fileData[index+i] != signature[i]) return false;
    return true;
  }
}
extension _Int8ListImageFileData on Uint8List {
  ImgFormat imageFormatAtIndex(int index) {
    if (this == null) return null;
    for (var format in ImgFormat.values) {
      if (format.checkHeaderSignature(this, index)) return format;
    }
    return null;
  }
  ImgFormat get imageFormat {
    return this.imageFormatAtIndex(0);
  }
}

class _MyHomePageState extends State<MyHomePage> {
  _MyHomePageState() {
    Image.asset("assets/thumbnail_missing.png");
  }

  GameFileType gameFileType;
  bool newThumbnailCorrect = false;
  Function() _saveDrone;
  Function() _exportThumbnail;
  Image newThumbnail = Image.asset("assets/image_blank.png");
  Image droneThumbnail = Image.asset("assets/thumbnail_blank.png");
  String fileName = "Choose a DRONE file";
  String fileNameFull = "";
  String imageName = "Choose an image";
  String imageWarning = "";
  Uint8List thumbnailBytes;
  Uint8List newThumbnailBytes;

  Uint8List droneFileStart;
  Uint8List droneFileTrail;

  void thumbnailLoadError() {setState(() {
    _exportThumbnail = null;
    _saveDrone = null;
    droneThumbnail = Image.asset("assets/thumbnail_missing.png");
    fileName += " (ERROR)";
  });}
  void thumbnailLoaded() {setState(() {
    _exportThumbnail = _exportThumbnailImpl;
    if (newThumbnailCorrect) _saveDrone = _saveDroneImpl;
  });}
  void droneThumbnailSet(Image thumbnail) {setState(() {
    droneThumbnail = thumbnail;
  });}
  void newThumbnailSet(Image thumbnail) {setState(() {
    newThumbnail = thumbnail;
  });}
  void newThumbnailLoaded() {setState(() {
    newThumbnailCorrect = true;
    if (_exportThumbnail != null) _saveDrone = _saveDroneImpl;
  });}
  void newThumbnailLoadError() {setState(() {
    imageWarning = "";
    newThumbnailCorrect = false;
    _saveDrone = null;
    newThumbnail = Image.asset("assets/thumbnail_missing.png");
    imageName += " (ERROR)";
  });}

  void _loadDrone() async {
    var gameDir = DIRECTORY_C.existsSync() ? DIRECTORY_C.path :
                    DIRECTORY_C_64.existsSync() ? DIRECTORY_C_64.path :
                    DIRECTORY_D.existsSync() ? DIRECTORY_D.path :
                    DIRECTORY_D_64.existsSync() ? DIRECTORY_D_64.path : null;
    var droneFile = File((await FileChooser.showOpenPanel(initialDirectory: gameDir, allowedFileTypes: [gameFileTypeGroup], allowsMultipleSelection: false)).paths.first);
    gameFileType = gameFileTypeFromExtension(Path.extension(droneFile.path));
    fileName = Path.basenameWithoutExtension(droneFile.path);
    fileNameFull = Path.basename(droneFile.path);
    WindowSize.setWindowTitle(fileName);
    var bytes = gameFileType.decode(droneFile.readAsBytesSync());
    try {
      var thumbnail = gameFileType.getEmbeddedThumbnail(bytes);
      thumbnailBytes = Uint8List.fromList(bytes.getRange(thumbnail.index, thumbnail.endIndex).toList());
      droneFileStart = Uint8List.fromList(bytes.getRange(0, thumbnail.index).toList());
      droneFileTrail = Uint8List.fromList(bytes.sublist(thumbnail.endIndex));
      droneThumbnailSet(Image.memory(thumbnailBytes));
      droneThumbnail.image.resolve(ImageConfiguration.empty).addListener(ImageStreamListener((ImageInfo info, bool synchronousCall) {
        thumbnailLoaded();
      }, onError: (dynamic error, StackTrace stackTrace) {
        thumbnailLoadError();
      }));
    }
    catch(ex) {
      thumbnailLoadError();
    }
  }

  void _loadImage() async {
    var imageFile = File((await FileChooser.showOpenPanel(allowedFileTypes: [supportedImageFileTypeGroup], allowsMultipleSelection: false)).paths.first);
    imageName = Path.basename(imageFile.path);
    try {
      newThumbnailSet(Image.file(imageFile));
      newThumbnail.image.resolve(ImageConfiguration.empty).addListener(ImageStreamListener((ImageInfo info, bool synchronousCall) {
        imageWarning = (info.image.width == 240 && info.image.height == 135) ? "" : "\nWARNING: A 240x135 image is recommended";
        newThumbnailBytes = imageFile.readAsBytesSync();
        newThumbnailLoaded();
      }, onError: (dynamic error, StackTrace stackTrace) {
        newThumbnailLoadError();
      }));
    }
    catch(ex) {
      newThumbnailLoadError();
    }
  }

  void _saveDroneImpl() async {
    var gameDir = DIRECTORY_C.existsSync() ? DIRECTORY_C.path :
                    DIRECTORY_C_64.existsSync() ? DIRECTORY_C_64.path :
                    DIRECTORY_D.existsSync() ? DIRECTORY_D.path :
                    DIRECTORY_D_64.existsSync() ? DIRECTORY_D_64.path : null;
    var saveResult = await FileChooser.showSavePanel(suggestedFileName: fileNameFull, initialDirectory: gameDir, allowedFileTypes: [gameFileType.fileTypeGroup]);
    if (!saveResult.canceled) {
      var droneFile = File(saveResult.paths.first);
      var newSizeBytes = Int32List.fromList([newThumbnailBytes.length]).buffer.asInt8List();
      var startSize = droneFileStart.length;
      droneFileStart[startSize-4] = (newSizeBytes.length > 0) ? newSizeBytes.first : 0;
      droneFileStart[startSize-3] = (newSizeBytes.length > 1) ? newSizeBytes[1] : 0;
      droneFileStart[startSize-2] = (newSizeBytes.length > 2) ? newSizeBytes[2] : 0;
      droneFileStart[startSize-1] = (newSizeBytes.length > 3) ? newSizeBytes[3] : 0;
      var bytes = Uint8List.fromList([droneFileStart, newThumbnailBytes, droneFileTrail].expand((b) => b).toList());
      droneFile.createSync();
      droneFile.writeAsBytes(gameFileType.encode(bytes), mode: FileMode.append);
    }
  }

  void _exportThumbnailImpl() async {
    var fileTypeGroup = thumbnailBytes.imageFormat.fileTypeGroup;
    var fileNameWithExtension = "$fileName${(fileTypeGroup.fileExtensions.isNotEmpty && fileTypeGroup.fileExtensions.first != "*") ? "."+fileTypeGroup.fileExtensions.first : ""}";
    var saveResult = (await FileChooser.showSavePanel(suggestedFileName: fileNameWithExtension, allowedFileTypes: [fileTypeGroup]));
    if (!saveResult.canceled) {
      var file = File(saveResult.paths.first);
      file.createSync();
      file.writeAsBytes(thumbnailBytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[Flexible(child:ListView(shrinkWrap: true, children: <Widget>[

            Card(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Padding(padding: EdgeInsets.all(10.2), child:Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      //TODO round resolution if blurry images get fixed
                      Flexible(child: SizedBox(width: 239.99, height: 134.99, child: droneThumbnail)),
                      Expanded(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ListTile(
                            title: Text("Drone or level"),
                            subtitle: Text(fileName),
                          ),
                        ],
                      )),
                    ],
                  )),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        child: const Text('Export thumbnail'),
                        onPressed: _exportThumbnail,
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        child: const Text('Select file'),
                        onPressed: _loadDrone,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                
                ],
              )
            ),

            Card(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Padding(padding: EdgeInsets.all(10.2), child:Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      //TODO round resolution if blurry images get fixed
                      Flexible(child: SizedBox(width: 239.99, height: 134.99, child: newThumbnail)),
                      Expanded(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ListTile(
                            title: Text('New thumbnail'),
                            subtitle: Text('$imageName$imageWarning'),
                          ),
                        ],
                      )),
                    ],
                  )),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        child: const Text('Select image'),
                        onPressed: _loadImage,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                
                ],
              )
            ),

            Padding(padding: EdgeInsets.fromLTRB(30, 10, 30, 10), child: Align(
              alignment: Alignment.bottomRight,
              child: MaterialButton(
                minWidth: 200,
                textColor: Colors.white,
                color: Colors.deepPurple,
                disabledColor: Colors.grey,
                onPressed: _saveDrone,
                child: const Text('Save'),
              )
            )),

          ]))],
        )
      )
    );
  }

}
