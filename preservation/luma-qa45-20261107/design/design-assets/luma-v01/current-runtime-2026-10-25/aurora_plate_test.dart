import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hiddify/core/widget/blizzard/blizzard_scene.dart';
void main(){
  final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('render actual product Aurora plate for editable pen design', (tester)async{
    final program=await ui.FragmentProgram.fromAsset('assets/shaders/blizzard_aurora_soft.frag');
    final shader=program.fragmentShader();
    final quietProgram=await ui.FragmentProgram.fromAsset('assets/shaders/blizzard_aurora.frag');
    final quietShader=quietProgram.fragmentShader();
    final plates=<String,List<int>>{};
    for(final config in [('phase084',0.25,0.42,true),('phase000',0.0,0.42,true),('quiet',0.0,0.18,false)]){
      final phase=config.$2;
      final painter=config.$4 ? BlizzardSoftAuroraPainter(phase:AlwaysStoppedAnimation(phase),shader:shader,intensity:config.$3,motion:false,resolutionScale:.75/tester.view.devicePixelRatio) : BlizzardAuroraPainter(phase:AlwaysStoppedAnimation(phase),shader:quietShader,intensity:config.$3,motion:false);
      await tester.pumpWidget(MaterialApp(home:RepaintBoundary(key:const ValueKey('plate'),child:ColoredBox(
        color:const Color(0xFF07151D),child:CustomPaint(painter:painter,size:Size.infinite)))));
      await tester.pump();
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:200)));
      final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('plate')));
      final image=await boundary.toImage(pixelRatio:3);
      try{plates[config.$1]=(await image.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List();}
      finally{image.dispose();}
    }
    binding.reportData={'plates':plates};
    await tester.pumpWidget(const SizedBox.shrink());
    shader.dispose();
    quietShader.dispose();
  });
}
