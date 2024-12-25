// ignore: unnecessary_import
import 'dart:ui';

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'custom_datatypes/member.dart';
import 'firebase_connections/singleton_firestore.dart';
import 'session_details.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'building_details.dart';

import 'package:fluttertoast/fluttertoast.dart';

class RoomEventDetails {
  String roomName;
  String eventName;

  RoomEventDetails(this.roomName, this.eventName);
}

class Room {
  List<Offset> roomVertices;
  String roomName;
  late Offset roomCenter;

  Room(this.roomVertices, this.roomName) {
    double sumdX = 0;
    double sumdY = 0;
    for (Offset roomVertex in roomVertices) {
      sumdX += roomVertex.dx;
      sumdY += roomVertex.dy;
    }

    this.roomCenter =
        Offset(sumdX / roomVertices.length, sumdY / roomVertices.length);
  }
}

class SetLocationMap extends StatefulWidget {
  const SetLocationMap({super.key});

  @override
  State<SetLocationMap> createState() => SetLocationMapWidgetState();
}

class SetLocationMapWidgetState extends State<SetLocationMap> {
  late int xposition;
  late int yposition;
  late double scale;

  late String floorName;
  late String buildingName;

  late String personName;

  late String appUserInstitutionID;

  Map<String, dynamic>? jsonData;
  List<Room> roomsOnFloor = <Room>[];
  List<RoomEventDetails> roomDetails = <RoomEventDetails>[];
  List<Offset> buildingBoundaries = <Offset>[];
  late Offset centering = const Offset(0, 0);
  late Offset previousOffset;
  late double initialScale; // To keep track of the previous drag position
  late Size drawingWindowSize;

  late bool mapLoadingUp = true;

  late Path path;
  late List<Path> roomPaths = <Path>[];
  late List<String> loadedRooms = <String>[];

  late bool inRoomSnackBar;

  String roomClicked = "";

  late Stream<int> timerBroadcastStream;
  late Stream eventBroadcastStream;

  Stream<QuerySnapshot>? eventStreamObj;
  Stream<QuerySnapshot>? memberStreamObj;

  @override
  void initState() {
    super.initState();

    xposition = 0;
    yposition = 0;
    scale = 0.6;

    buildingName = BuildingDetails.buildings[0];

    personName = "";
    floorName = BuildingDetails.floors[0];

    appUserInstitutionID = SessionDetails.institution_id;
    previousOffset = Offset.zero;
    initialScale = 1.0;

    loadFloors();

    eventStreamObj = FirestoreService()
        .firestore
        .collection("events")
        .where("institution_id", isEqualTo: appUserInstitutionID)
        .where("building", isEqualTo: buildingName)
        .where("floor", isEqualTo: floorName)
        .snapshots();

    memberStreamObj = FirestoreService()
        .firestore
        .collection("institution_members")
        .where("institution_id", isEqualTo: appUserInstitutionID)
        .where("rfid_location",
            isGreaterThanOrEqualTo: "$buildingName/$floorName")
        .where("rfid_location",
            isLessThanOrEqualTo: "$buildingName/$floorName\uf8ff")
        .snapshots();

    timerBroadcastStream = timerStream1.asBroadcastStream();
    eventBroadcastStream = eventStream().asBroadcastStream();
  }

  final Stream<int> timerStream1 = Stream<int>.periodic(
    Duration(seconds: 10),
    (count) => count,
  );

  Stream<QuerySnapshot> eventStream() {
    //print(appUserInstitutionID as String);
    //print(buildingName + floorName);
    return FirestoreService()
        .firestore
        .collection("events")
        .where("institution_id", isEqualTo: appUserInstitutionID)
        .where("building", isEqualTo: buildingName)
        .where("floor", isEqualTo: floorName)
        .snapshots();
  }

  Future<void> updateLocation(String location) async {
    print("update location reached");

    bool inRoom;

    QuerySnapshot snapshot = await FirestoreService()
        .firestore
        .collection('institution_members')
        .where('institution_id', isEqualTo: appUserInstitutionID)
        .where('id', isEqualTo: SessionDetails.id)
        .limit(1)
        .get();

    Map<String, dynamic> userData =
        snapshot.docs[0].data() as Map<String, dynamic>;

    if (userData['rfid_location'] != location) {
      inRoom = true;
    } else {
      inRoom = !userData['in_room'];
    }

    await FirestoreService()
        .firestore
        .collection('institution_members')
        .doc(snapshot.docs[0].id)
        .update({
      'rfid_location': location,
      'in_room': inRoom,
      'last_location_entry': Timestamp.now()
    });

    inRoomSnackBar = inRoom;
  }

  void changeFloorAndBuilding(floor, building) {
    setState(() {
      mapLoadingUp = true;
      floorName = floor;
      buildingName = building;
      roomClicked = "";
      print(floorName);
      //buildingOffsetsLoad();
      loadFloors();

      eventStreamObj = FirestoreService()
          .firestore
          .collection("events")
          .where("institution_id", isEqualTo: appUserInstitutionID)
          .where("building", isEqualTo: buildingName)
          .where("floor", isEqualTo: floorName)
          .snapshots();

      memberStreamObj = FirestoreService()
          .firestore
          .collection("institution_members")
          .where("institution_id", isEqualTo: appUserInstitutionID)
          .where("rfid_location",
              isGreaterThanOrEqualTo: "$buildingName/$floorName")
          .where("rfid_location",
              isLessThanOrEqualTo: "$buildingName/$floorName\uf8ff")
          .snapshots();
    });
  }

  Future<void> loadFloors() async {
    roomsOnFloor.clear();

    Map<String, dynamic> institution = {};
    String institutionDocName = '';
    String buildingDocName = '';
    Map<String, dynamic> building = {};
    List<List<int>> building_boundaries = [];
    late Map<String, dynamic> floor = {};

    QuerySnapshot snapshot = await FirestoreService()
        .firestore
        .collection('institution_buildings')
        .where('institution_id', isEqualTo: appUserInstitutionID)
        .limit(1)
        .get();

    for (QueryDocumentSnapshot doc in snapshot.docs) {
      institutionDocName = doc.id;
      institution = doc.data() as Map<String, dynamic>;
    }

    QuerySnapshot snapshot1 = await FirestoreService()
        .firestore
        .collection('institution_buildings')
        .doc(institutionDocName)
        .collection('buildings')
        .where("building_name", isEqualTo: buildingName)
        .limit(1)
        .get();

    for (QueryDocumentSnapshot doc in snapshot1.docs) {
      buildingDocName = doc.id;
      building = doc.data() as Map<String, dynamic>;
    }

    building_boundaries = jsonDecode(building['building_boundaries'])
        .map<List<int>>((item) => List<int>.from(item))
        .toList();

    for (List<int> point in building_boundaries) {
      buildingBoundaries.add(Offset(point[0].toDouble(), point[1].toDouble()));
      //print(Offset(point[0].toDouble(),point[1].toDouble()));
    }

    QuerySnapshot snapshot2 = await FirestoreService()
        .firestore
        .collection('institution_buildings')
        .doc(institutionDocName)
        .collection('buildings')
        .doc(buildingDocName)
        .collection('floors')
        .where('floor_name', isEqualTo: floorName)
        .limit(1)
        .get();

    for (QueryDocumentSnapshot doc in snapshot2.docs) {
      //buildingDocName = doc.id;
      floor = doc.data() as Map<String, dynamic>;
      floor = json.decode(floor['rooms_on_floor']) as Map<String, dynamic>;
    }

    setState(() {
      floor.forEach((key, value) {
        List<Offset> points = (value as List).map<Offset>((item) {
          double x = item[0].toDouble();
          double y = item[1].toDouble();
          return Offset(x, y);
        }).toList();

        roomsOnFloor.add(Room(points, key));
      });

      //for (Room room in roomsOnFloor) {
      //  if (room.roomName == memberSearched.room) {
      //    centering = room.roomCenter;
      //  }
      //}

      mapLoadingUp = false;
    });
  }

  void moveRight() {
    setState(() {
      xposition -= 20;
    });
  }

  void moveUp() {
    setState(() {
      yposition += 20;
    });
  }

  void moveDown() {
    setState(() {
      yposition -= 20;
    });
  }

  void moveLeft() {
    setState(() {
      xposition += 20;
    });
  }

  void zoomIn() {
    setState(() {
      scale += 0.3;
    });
  }

  void zoomOut() {
    setState(() {
      scale -= 0.3;
    });
  }

  void putToast(String message) {
    Fluttertoast.showToast(
        msg: message,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 1,
        backgroundColor: Colors.white,
        textColor: Colors.black,
        fontSize: 16.0);
  }

  void getPathAndSize(
      List<Path> roomPaths, Size size, List<String> loadedRooms) {
    this.drawingWindowSize = size;
    this.roomPaths = roomPaths;
    this.loadedRooms = loadedRooms;
  }

  Offset scaler(Offset unscaledPoint) {
    return Offset(
        unscaledPoint.dx -
            (drawingWindowSize.width / 2 - scale * (centering.dx)),
        unscaledPoint.dy -
            (drawingWindowSize.height / 2 - scale * (centering.dy)));
  }

  void _onTapDown(TapDownDetails details) {
    for (int i = 0; i < this.roomPaths.length; i++) {
      if (this.roomPaths[i].contains(scaler(details.localPosition))) {
        String location = this.buildingName +
            "/" +
            this.floorName +
            "/" +
            this.loadedRooms[i];

        print(location);

        setState(() {
          roomClicked = this.loadedRooms[i];
        });
      }
    }
  }

  void _onDoubleTapDown(TapDownDetails details) async {
    for (int i = 0; i < this.roomPaths.length; i++) {
      if (this.roomPaths[i].contains(scaler(details.localPosition))) {
        String location = this.buildingName +
            "/" +
            this.floorName +
            "/" +
            this.loadedRooms[i];

        print(location);

        await updateLocation(location);
        print("done");

        if (inRoomSnackBar) {
          putToast("You entered " + location);
        } else {
          putToast("You exited " + location);
        }
      }
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    initialScale = scale;
    previousOffset = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if ((details.scale - scale).abs() > 0.01 ||
        (details.focalPoint - previousOffset).distance > 5) {
      setState(() {
        scale = initialScale * details.scale;
        xposition -=
            ((1 / scale) * (details.focalPoint.dx - previousOffset.dx)).toInt();
        yposition -=
            ((1 / scale) * (details.focalPoint.dy - previousOffset.dy)).toInt();
        previousOffset = details.focalPoint;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Column(
        children: [
          Row(
            children: [
              TextButton(onPressed: this.moveLeft, child: const Text("<")),
              TextButton(onPressed: this.moveRight, child: const Text(">")),
              TextButton(onPressed: this.moveUp, child: const Text("^")),
              TextButton(onPressed: this.moveDown, child: const Text("v")),
              TextButton(onPressed: this.zoomIn, child: const Text("+")),
              TextButton(onPressed: this.zoomOut, child: const Text("-")),
            ],
          ),
          mapLoadingUp
              ? Container(
                  width: double.infinity,
                  height: 500,
                  color: const Color.fromARGB(255, 255, 255, 255),
                  child: Center(child: CircularProgressIndicator()))
              : StreamBuilder(
                  stream: eventStreamObj,
                  builder: (context, eventSnapshot) {
                    if (eventSnapshot.hasError) {
                      return Container(
                        width: double.infinity,
                        height: 100,
                        color: const Color.fromARGB(255, 255, 255, 255),
                        child: Text("Error fetching data"),
                      );
                    }

                    if (eventSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return Container(
                          width: double.infinity,
                          height: 500,
                          color: const Color.fromARGB(255, 255, 255, 255),
                          child: Center(child: CircularProgressIndicator()));
                    }

                    if (!eventSnapshot.hasData) {
                      return RepaintBoundary(
                          child: GestureDetector(
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: _onScaleUpdate,
                        onDoubleTapDown: _onDoubleTapDown,
                        onTapDown: _onTapDown,
                        child: Container(
                          width: double.infinity,
                          height: 400,
                          color: const Color.fromARGB(255, 255, 255, 255),
                          child: CustomPaint(
                            painter: PointsPainter(
                                xposition,
                                yposition,
                                scale,
                                roomsOnFloor,
                                buildingBoundaries,
                                centering,
                                getPathAndSize,
                                roomClicked,
                                buildingName,
                                floorName),
                          ),
                        ),
                      ));
                    }

                    Map<String, Map<String, dynamic>> eventDetailsOptimized =
                        {};
                    Map<String, dynamic> eventDetail = {};

                    for (var doc in eventSnapshot.data!.docs) {
                      eventDetail = doc.data() as Map<String, dynamic>;
                      String location = eventDetail['room'];
                      eventDetailsOptimized.addAll({location: eventDetail});
                    }

                    print(eventDetailsOptimized);

                    return StreamBuilder(
                      stream: memberStreamObj,
                      builder: (context, memberSnapshot) {
                        if (memberSnapshot.hasError) {
                          return Container(
                            width: double.infinity,
                            height: 100,
                            color: const Color.fromARGB(255, 255, 255, 255),
                            child: Text("Error fetching data"),
                          );
                        }

                        if (memberSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Container(
                              width: double.infinity,
                              height: 500,
                              color: const Color.fromARGB(255, 255, 255, 255),
                              child:
                                  Center(child: CircularProgressIndicator()));
                        }

                        if (!memberSnapshot.hasData) {
                          return RepaintBoundary(
                              child: GestureDetector(
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            onDoubleTapDown: _onDoubleTapDown,
                            onTapDown: _onTapDown,
                            child: Container(
                              width: double.infinity,
                              height: 400,
                              color: const Color.fromARGB(255, 255, 255, 255),
                              child: CustomPaint(
                                painter: PointsPainter(
                                    xposition,
                                    yposition,
                                    scale,
                                    roomsOnFloor,
                                    buildingBoundaries,
                                    centering,
                                    getPathAndSize,
                                    roomClicked,
                                    buildingName,
                                    floorName),
                              ),
                            ),
                          ));
                        }

                        /*
                        Map<String, Map<String, dynamic>>
                            eventDetailsOptimized = {};
                        Map<String, dynamic> eventDetail = {};

                        for (var doc in eventSnapshot.data!.docs) {
                          eventDetail = doc.data() as Map<String, dynamic>;
                          String location = eventDetail['room'];
                          eventDetailsOptimized.addAll({location: eventDetail});
                        }
                        */

                        List<Map<String, dynamic>> attendeesList = [];
                        for (var doc in memberSnapshot.data!.docs) {
                          print(doc.data() as Map<String, dynamic>);
                          Map<String, dynamic> attendee =
                              doc.data() as Map<String, dynamic>;

                          attendeesList.add(attendee);
                        }

                        print("Member : ");
                        print(memberSnapshot.data!.size);
                        int numberOfAttendees = memberSnapshot.data!.size;
                        //print(memerSnapshot.data!.docs[0].data() as Map<String,dynamic>);

                        return Column(children: [
                          GestureDetector(
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            onDoubleTapDown: _onDoubleTapDown,
                            onTapDown: _onTapDown,
                            child: Container(
                              width: double.infinity,
                              height: 400,
                              color: const Color.fromARGB(255, 255, 255, 255),
                              child: CustomPaint(
                                painter: PointsPainter(
                                    xposition,
                                    yposition,
                                    scale,
                                    roomsOnFloor,
                                    buildingBoundaries,
                                    centering,
                                    getPathAndSize,
                                    roomClicked,
                                    buildingName,
                                    floorName),
                              ),
                            ),
                          ),
                          MemberDetails(
                              eventDetailsOptimized,
                              roomClicked,
                              floorName,
                              buildingName,
                              attendeesList),
                        ]);
                      },
                    );
                  },
                ),
        ],
      ),
    );
  }
}

class PointsPainter extends CustomPainter {
  final int xposition;
  final int yposition;
  final double scale;
  final List<Room> roomsOnFloor;
  String finalTextDisplayed = "";
  double sumdX = 0;
  double sumdY = 0;
  double avgdY = 0;
  double avgdX = 0;
  double translatedTextX = 0;
  double translatedTextY = 0;
  List<Offset> buildingBoundaries;
  Offset roomCentering;

  Offset buildingBoundariesSum = Offset(0, 0);

  late List<Path> roomPaths = <Path>[];
  late List<String> loadedRooms = <String>[];

  String roomClicked;
  String buildingName;
  String floorName;

  final void Function(List<Path>, Size, List<String>) sendPath;

  final pathPaintStrokeAbsent = Paint()
    ..strokeWidth = 2.0
    ..color = const Color.fromARGB(255, 0, 154, 82)
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  final pathPaintStrokePresent = Paint()
    ..strokeWidth = 6.0
    ..color = const Color.fromARGB(255, 0, 154, 82)
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  final pathPaintFill = Paint()
    ..strokeWidth = 2.0
    ..color = const Color.fromARGB(255, 59, 255, 164)
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.fill;

  PointsPainter(
      this.xposition,
      this.yposition,
      this.scale,
      this.roomsOnFloor,
      this.buildingBoundaries,
      this.roomCentering,
      this.sendPath,
      this.roomClicked,
      this.buildingName,
      this.floorName);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    //canvas.translate((size.width / 2 - scale * (roomCentering.dx)),
    //    (size.height / 2 - scale * (roomCentering.dy)));

    final textStyle = TextStyle(
      color: const Color.fromARGB(255, 0, 154, 82),
      fontSize: scale * 20,
    );

    List<Offset> buildingVerticesTranformed = <Offset>[];
    Path buildingPath = Path();
    bool buildingPointFirst = true;

    for (Offset buildingVertex in buildingBoundaries) {
      Offset transformedBuildingVertex = Offset(
          scale * (buildingVertex.dx - xposition),
          scale * (buildingVertex.dy - yposition));
      buildingVerticesTranformed.add(transformedBuildingVertex);

      buildingBoundariesSum = Offset(
          buildingBoundariesSum.dx + transformedBuildingVertex.dx,
          buildingBoundariesSum.dy + transformedBuildingVertex.dy);
    }

    // Earlier this code broke the rectangle clicking
    // If you implement something, do it completely
    //roomCentering = Offset(buildingBoundariesSum.dx / buildingBoundaries.length, buildingBoundariesSum.dy / buildingBoundaries.length);
    canvas.translate((size.width / 2 - scale * (roomCentering.dx)),
        (size.height / 2 - scale * (roomCentering.dy)));

    for (int i = 0; i < buildingVerticesTranformed.length; i++) {
      Offset start = buildingVerticesTranformed[i];
      Offset end = buildingVerticesTranformed[
          (i + 1) % buildingVerticesTranformed.length];

      if (buildingPointFirst) {
        buildingPath.moveTo(start.dx, start.dy);
        buildingPath.lineTo(end.dx, end.dy);
        buildingPointFirst = false;
      } else {
        buildingPath.lineTo(end.dx, end.dy);
      }
    }

    buildingPath.close();
    canvas.drawPath(buildingPath, pathPaintStrokeAbsent);

    for (Room room in roomsOnFloor) {
      String currentRoomName = room.roomName;
      bool firstPoint = true;
      Path roomPath = Path();

      List<Offset> pointsTransformed = room.roomVertices.map((point) {
        return Offset(
            scale * (point.dx - xposition), scale * (point.dy - yposition));
      }).toList();

      bool noneInside = true;
      for (int i = 0; i < pointsTransformed.length; i++) {
        if ((pointsTransformed[i].dx <
                    size.width -
                        (size.width / 2 - scale * (roomCentering.dx)) &&
                pointsTransformed[i].dx >
                    -1 * (size.width / 2 - scale * (roomCentering.dx))) &&
            (pointsTransformed[i].dy <
                    size.height -
                        (size.height / 2 - scale * (roomCentering.dy)) &&
                pointsTransformed[i].dy >
                    -1 * (size.height / 2 - scale * (roomCentering.dy)))) {
          noneInside = false;
          break;
        }
      }

      //print("\n Event Details  \n" + eventDetails[0].toString());

      canvas.drawPoints(PointMode.points, [Offset(390, 500)], pathPaintFill);

      if (noneInside) {
        //print(room.roomName);
        //print("Not calculated");
        continue;
      }

      for (int i = 0; i < pointsTransformed.length; i++) {
        Offset start = pointsTransformed[i];
        Offset end = pointsTransformed[(i + 1) % pointsTransformed.length];
        if (firstPoint) {
          roomPath.moveTo(start.dx, start.dy);
          roomPath.lineTo(end.dx, end.dy);
          firstPoint = false;
        } else {
          roomPath.lineTo(end.dx, end.dy);
        }
      }

      roomPaths.add(roomPath);
      loadedRooms.add(currentRoomName);

      if (currentRoomName == roomClicked) {
        canvas.drawPath(roomPath, pathPaintStrokePresent);
        canvas.drawPath(roomPath, pathPaintFill);
      } else {
        canvas.drawPath(roomPath, pathPaintStrokeAbsent);
      }

      finalTextDisplayed = currentRoomName;

      TextSpan textSpan = TextSpan(
        text: finalTextDisplayed,
        style: textStyle,
      );

      TextPainter textPainter = TextPainter(
        textAlign: TextAlign.center,
        text: textSpan,
        textDirection: TextDirection.ltr,
      );

      textPainter.layout(
        minWidth: 0,
        maxWidth: size.width,
      );

      sumdX = 0;
      sumdY = 0;
      for (Offset point in pointsTransformed) {
        sumdX += point.dx;
        sumdY += point.dy;
      }
      avgdY = sumdY / pointsTransformed.length;
      avgdX = sumdX / pointsTransformed.length;

      textPainter.paint(
          canvas,
          Offset(
              avgdX - textPainter.width / 2, avgdY - textPainter.height / 2));
    }

    sendPath(roomPaths, size, loadedRooms);
  }

  @override
  bool shouldRepaint(covariant PointsPainter oldDelegate) {
    return oldDelegate.xposition != xposition ||
        oldDelegate.yposition != yposition ||
        oldDelegate.scale != scale ||
        oldDelegate.roomsOnFloor != roomsOnFloor;
  }
}

class MemberDetails extends StatelessWidget {
  List<ListTile> eventDetailTiles = <ListTile>[];

  Map<String, Map<String, dynamic>> eventDetailsOptimized = {};
  String roomClicked;
  String floorName;
  String buildingName;
  List<Map<String, dynamic>> attendeesList;
  late int numberOfAttendees = 0;

  List<Map<String, dynamic>> getAttendeesInRoom(
      List<Map<String, dynamic>> attendeesList, String location) {
    List<Map<String, dynamic>> attendeesInRoom = [];
    for (Map<String, dynamic> attendee in attendeesList) {
      if (attendee['rfid_location'] == location) {
        attendeesInRoom.add(attendee);
        numberOfAttendees++;
      }
    }

    return attendeesInRoom;
  }

  MemberDetails(
      this.eventDetailsOptimized,
      this.roomClicked,
      this.floorName,
      this.buildingName,
      this.attendeesList) {
    if (eventDetailsOptimized[roomClicked] == null) {
      eventDetailTiles.add(const ListTile(
        dense: true,
        title: Text("No events"),
        minTileHeight: 0,
      ));
    }
    else
    {
      eventDetailTiles.add(ListTile(
      dense: true,
      title: Text(
        "Event Name : " + eventDetailsOptimized[roomClicked]!['name'].toString(),
        style: TextStyle(fontSize: 12),
      ),
      minTileHeight: 0,
    ));
    }

      String location = "$buildingName/$floorName/$roomClicked";
      List<Map<String, dynamic>> attendeesInRoom =
          getAttendeesInRoom(attendeesList, location);

    eventDetailTiles.add(ListTile(
        dense: true, title: Text("Number of Attendees : $numberOfAttendees"), minTileHeight: 0,));

    for (Map<String, dynamic> attendee in attendeesInRoom) {
        eventDetailTiles.add(ListTile(
          dense: true,
          title: Text(attendee['name']),
          minTileHeight: 0,
        ));
      }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey, width: 1),
        ),
        width: 500,
        height: 200,
        child: ListView(padding: EdgeInsets.zero, children: eventDetailTiles));
  }
}
