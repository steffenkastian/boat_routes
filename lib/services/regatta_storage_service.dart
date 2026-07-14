import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/regatta.dart';

class RegattaStorageService {
  final _collection =
      FirebaseFirestore.instance.collection('regattas').withConverter<Regatta>(
            fromFirestore: (doc, _) => Regatta.fromDoc(doc),
            toFirestore: (regatta, _) => regatta.toMap(),
          );

  Future<void> addRegatta(Regatta regatta) => _collection.add(regatta);

  Future<List<Regatta>> searchByPlz(String plz) async {
    final snapshot = await _collection.where('plz', isEqualTo: plz).get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }
}
