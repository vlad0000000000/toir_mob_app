// import 'dart:convert';
// import 'dart:io';
//
// import 'package:awesome_dialog/awesome_dialog.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_markdown/flutter_markdown.dart';
// import 'package:go_router/go_router.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:mobile_scanner/mobile_scanner.dart';
// import 'package:flutter_screenutil/flutter_screenutil.dart';
// import 'package:provider/provider.dart';
// import 'package:qr_machine_scanner/global_state.dart';
// import 'package:qr_machine_scanner/src/data/data_provider.dart';
// import 'package:qr_machine_scanner/src/model/check.dart';
// import 'package:qr_machine_scanner/src/model/machine.dart';
// import 'package:qr_machine_scanner/src/utils/dialogs.dart';
// import 'package:qr_machine_scanner/src/widgets/button_with_select_dialog.dart';
// import 'package:qr_machine_scanner/src/widgets/select_image_button.dart';
// import 'package:qr_machine_scanner/src/widgets/square_button.dart';
// import 'package:qr_machine_scanner/strings.dart';
// import 'package:themed/themed.dart';
// import '../settings/settings.dart';
// import '../style/palette.dart';
// import '../style/text_styles.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:gallery_saver_plus/gallery_saver.dart';
//
// class QRResultScreen extends StatefulWidget {
//   final Machine machine;
//
//   const QRResultScreen(this.machine, {super.key});
//
//   @override
//   State<QRResultScreen> createState() => _QRResultScreenState();
// }
//
// class _QRResultScreenState extends State<QRResultScreen> {
//   final descController = TextEditingController();
//   final imageData1Controller = SelectImageButtonController();
//   final imageData2Controller = SelectImageButtonController();
//   final imageData3Controller = SelectImageButtonController();
//   final priorityController = ButtonWithSelectDialogController();
//   final problemController = ButtonWithSelectDialogController();
//   String problem = '';
//
//   Widget checkControls() {
//     List<Widget> addButtons = [
//       SelectImageButton(
//         controller: imageData1Controller,
//       ),
//       SelectImageButton(
//         controller: imageData2Controller,
//       ),
//       SelectImageButton(
//         controller: imageData3Controller,
//       ),
//
//       // addImageButton(() async {
//       //   FilePickerResult? result = await FilePicker.platform.pickFiles();
//       //
//       //   if (result != null) {
//       //     File file = File(result.files.single.path!);
//       //   } else {
//       //     // User canceled the picker
//       //   }
//       // }),
//       // addImageButton(() async {
//       //   final ImagePicker picker = ImagePicker();
//       //
//       //   final XFile? image = await picker.pickImage(
//       //     source: ImageSource.camera,
//       //     // source: ImageSource.
//       //   );
//       //
//       //   if (image != null) GallerySaver.saveImage(image.path);
//       // }),
//       // addImageButton(() async {
//       //   final ImagePicker picker = ImagePicker();
//       //
//       //   final XFile? image = await picker.pickImage(
//       //     source: ImageSource.gallery,
//       //   );
//       // }),
//     ];
//
//     return Column(spacing: 8, children: [
//       TextFormField(
//         // obscureText:false,
//         maxLines: 8,
//         // expands:true,
//         controller: descController,
//         // obscureText: true,
//         // style: TextStyle(backgroundColor: Colors.white,decorationColor: Colors.white, color: Colors.white),
//         decoration: InputDecoration(
//             floatingLabelAlignment: FloatingLabelAlignment.start,
//             border: const OutlineInputBorder(),
//             fillColor: Colors.white,
//             filled: true,
//             alignLabelWithHint: true,
//             hoverColor: Colors.white,
//             labelText: Strings.checkDescription),
//         validator: (value) {
//           // if (value == null || value.isEmpty) {
//           //   return Strings.passwordHelp;
//           // }
//           return null;
//         },
//       ),
//       Row(
//         spacing: 8,
//         children: [
//           Expanded(
//               child: Column(
//                 spacing: 4,
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text("Проблема"),
//               Row(
//                 children: [
//                   ButtonWithSelectDialog(
//                       controller: problemController,
//                       dialogTitle: "Выберите проблему",
//                       buttonText: "Выбрать",
//                       items: [
//                         "Не включается",
//                         "Не выключается",
//                         "Шумит",
//                         "Искрит",
//                         "Дымит"
//                       ]),
//                 ],
//               )
//             ],
//           )),
//           Expanded(
//               child: Column(
//                 spacing: 4,
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text("Приоритет"),
//               Row(
//                 children: [
//                   ButtonWithSelectDialog(
//                       controller: priorityController,
//                       dialogTitle: "Выберите приоритет",
//                       buttonText: "Выбрать",
//                       items: [
//                         "Низкий",
//                         "Средний",
//                         "Высокий",
//                       ])
//                 ],
//               )
//             ],
//           )),
//         ],
//       ),
//       SizedBox(
//           height: 160,
//           child: Row(
//             crossAxisAlignment: CrossAxisAlignment.stretch,
//             spacing: 8,
//             children: addButtons,
//           )),
//       SizedBox()
//       // addImageButton(() async {
//       //   FilePickerResult? result = await FilePicker.platform.pickFiles();
//       //
//       //   if (result != null) {
//       //     File file = File(result.files.single.path!);
//       //   } else {
//       //     // User canceled the picker
//       //   }
//       // }),
//       // addImageButton(() async {
//       //   final ImagePicker picker = ImagePicker();
//       //
//       //   final XFile? image = await picker.pickImage(
//       //     source: ImageSource.camera,
//       //   );
//       //
//       //   if (image != null) GallerySaver.saveImage(image.path);
//       // }),
//       // addImageButton(() async {
//       //   final ImagePicker picker = ImagePicker();
//       //
//       //   final XFile? image = await picker.pickImage(
//       //     source: ImageSource.gallery,
//       //   );
//       // }),
//       // ElevatedButton(onPressed: () {}, child: Text(Strings.finishCheck)),
//       // SizedBox(
//       //   height: 32,
//       // )
//     ]);
//   }
//
//   Widget passport() {
//     var passportType = 1;
//     // image + text
//     if (passportType == 1) {
//       return Column(
//         spacing: 8,
//         mainAxisAlignment: MainAxisAlignment.start,
//         children: [
//           // const Image(image: AssetImage('assets/images/lathe.jpg')),
//           Image.memory(base64Decode(widget.machine.imageData)),
//           Row(children: [Expanded(child: MarkdownBody(data: """
// **Название**: ${widget.machine.name}
//
// **Номер**: ${widget.machine.id}
//
// ${widget.machine.description}
//     """))],),
//           // FutureBuilder<String>(
//           //   future: rootBundle.loadString('assets/text/lathe.txt'),
//           //   builder: (context, snapshot) {
//           //     if (snapshot.hasData) {
//           //       return Text(snapshot.data!);
//           //     } else if (snapshot.hasError) {
//           //       return Text('${snapshot.error}');
//           //     }
//           //
//           //     // By default, show a loading spinner.
//           //     return const CircularProgressIndicator();
//           //   },
//           // ),
//           // checkControls(),
//           // SizedBox()
//         ],
//       );
//     }
//
//     // pdf
//     if (passportType == 2) {}
//     return SizedBox();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final palette = context.watch<Palette>();
//     final textStyles = context.watch<TextStyles>();
//     final dataProvider = context.watch<DataProvider>();
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(Strings.qrResultScreenTitle),
//       ),
//       body: Padding(
//         padding: EdgeInsets.symmetric(horizontal: 8),
//         child: Column(
//           spacing: 8,
//           children: [
//             Expanded(
//                 child: SingleChildScrollView(
//               child: Column(
//                 spacing: 16,
//                 children: [passport(), checkControls()],
//               ),
//             )),
//             // passport(),
//             Row(
//               spacing: 8,
//               children: [
//                 Expanded(
//                     child: SquareButton(
//                         color: Colors.green,
//                         onPressed: () {
//                           Dialogs.areYouSure(context, onOk: () async {
//                             await dataProvider.sendMachineCheck(Check(
//                                 userId: GlobalState.authUser.id,
//                                 machineId: widget.machine.id,
//                                 status: 1,
//                                 images: [
//                                   imageData1Controller.value,
//                                   imageData2Controller.value,
//                                   imageData3Controller.value,
//                                 ],
//                                 description: descController.text,
//                                 priority: priorityController.value,
//                                 problem: problemController.value,
//                                 ts: GlobalState.now));
//                             GoRouter.of(context).go("/qr_scanner");
//                           });
//                         },
//                         child: Icon(
//                           Icons.thumb_up,
//                           color: Colors.white,
//                           size: 32,
//                         ))),
//                 Expanded(
//                     child: SquareButton(
//                         color: Colors.red,
//                         onPressed: () async {
//                           Dialogs.areYouSure(context, onOk: () async {
//                             await dataProvider.sendMachineCheck(Check(
//                                 userId: GlobalState.authUser.id,
//                                 machineId: widget.machine.id,
//                                 status: 2,
//                                 images: [
//                                   imageData1Controller.value,
//                                   imageData2Controller.value,
//                                   imageData3Controller.value,
//                                 ],
//                                 description: descController.text,
//                                 priority: priorityController.value,
//                                 problem: problemController.value,
//                                 ts: GlobalState.now));
//                             GoRouter.of(context).go("/qr_scanner");
//                           });
//                         },
//                         child: Icon(
//                           Icons.thumb_down,
//                           color: Colors.white,
//                           size: 32,
//                         ))),
//               ],
//             ),
//             // checkControls()
//             SizedBox()
//           ],
//         ),
//       ),
//     );
//   }
//
//   @override
//   void initState() {
//     super.initState();
//
//     // Preload ad for the win screen.
//     // final adsRemoved =
//     //     context.read<InAppPurchaseController?>()?.adRemoval.active ?? false;
//     // if (!adsRemoved) {
//     //   final adsController = context.read<AdsController?>();
//     //   adsController?.preloadAd();
//     // }
//   }
// }
