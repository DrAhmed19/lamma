import 'package:flutter/foundation.dart';

// عدّاد أداء صغير يطلع بزاوية اللعبة (مؤقتاً، حتى نعرف سبب التقطيع بالآيباد):
// fps = إطارات بالثانية، أبطأ = أطول إطار، net = حالات السيرفر بالثانية وحجمها.
final perfText = ValueNotifier<String>('');

int _frames = 0;
double _sum = 0, _worst = 0;
int netMsgs = 0, netBytes = 0;

void perfFrame(double realDt) {
  _frames++;
  _sum += realDt;
  if (realDt > _worst) _worst = realDt;
  if (_sum >= 1) {
    perfText.value = 'fps ${(_frames / _sum).round()} · أبطأ ${(_worst * 1000).round()}ms · net ${netMsgs}/s ${(netBytes / 1024).toStringAsFixed(1)}KB';
    _frames = 0;
    _sum = 0;
    _worst = 0;
    netMsgs = 0;
    netBytes = 0;
  }
}
