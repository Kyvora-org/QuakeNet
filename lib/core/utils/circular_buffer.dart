import 'dart:collection';

class CircularBuffer<T> {
  final int capacity;
  final ListQueue<T> _queue;

  CircularBuffer(this.capacity) : _queue = ListQueue<T>(capacity);

  void add(T item) {
    if (_queue.length >= capacity) {
      _queue.removeFirst();
    }
    _queue.addLast(item);
  }

  void clear() {
    _queue.clear();
  }

  List<T> toList() {
    return _queue.toList(growable: false);
  }

  int get length => _queue.length;

  bool get isEmpty => _queue.isEmpty;
  
  bool get isNotEmpty => _queue.isNotEmpty;
}
