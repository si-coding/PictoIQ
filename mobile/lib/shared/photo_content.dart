import 'dart:math' as math;

/// One thing the on-device image labeller recognised in a photo.
class PhotoLabel {
  const PhotoLabel(this.name, this.confidence);

  final String name;

  /// 0 to 1.
  final double confidence;
}

/// Names the labeller uses for people, in lower case.
const peopleLabels = {
  'person', 'people', 'human', 'face', 'smile', 'selfie', 'crowd', 'child',
  'baby', 'toddler', 'boy', 'girl', 'man', 'woman', 'hair',
  'facial expression', 'forehead', 'skin', 'beard', 'eyebrow', 'eyelash',
  'chin', 'nose', 'cheek', 'lip', 'mouth', 'bride', 'groom', 'friendship',
  'hug', 'kiss',
};

/// Names for places and nature.
const sceneryLabels = {
  'sky', 'cloud', 'mountain', 'sea', 'ocean', 'beach', 'lake', 'river',
  'waterfall', 'tree', 'forest', 'flower', 'plant', 'grass', 'field',
  'sunset', 'sunrise', 'landscape', 'hill', 'valley', 'snow', 'desert',
  'island', 'coast', 'shore', 'wave', 'water', 'nature', 'garden', 'rock',
  'cliff', 'cityscape', 'skyline', 'skyscraper', 'sunlight', 'horizon',
  'natural landscape', 'natural environment', 'highland', 'meadow',
  'pasture', 'canyon', 'bay', 'building', 'architecture', 'bridge', 'tower',
  'temple', 'palace', 'castle', 'monument', 'city', 'street', 'road', 'sand',
  'dusk', 'dawn',
};

/// Names for documents, screens and everyday objects: what the "people and
/// scenery only" filter leaves out.
const objectLabels = {
  'text', 'document', 'paper', 'font', 'screenshot', 'display device',
  'screen', 'projection screen', 'projector', 'presentation', 'computer',
  'laptop', 'monitor', 'television', 'electronic device', 'gadget',
  'technology', 'multimedia', 'poster', 'product', 'advertising',
  'whiteboard', 'receipt', 'handwriting', 'number', 'diagram', 'menu',
  'label', 'book', 'publication', 'signage', 'sign', 'furniture', 'table',
  'tableware', 'dishware', 'food', 'dish', 'cuisine', 'drink', 'bottle',
  'cup', 'mug', 'plate', 'toy', 'car', 'bicycle', 'shoe', 'bag', 'jewellery',
  'watch', 'mobile phone', 'phone', 'tool', 'machine', 'appliance',
  'kitchen appliance', 'home appliance', 'packaging', 'box', 'card', 'brand',
  'logo', 'pen', 'office supplies', 'musical instrument', 'bookcase',
  'shelf', 'cable', 'electronics', 'output device', 'input device',
  'personal computer', 'computer monitor', 'flat panel display',
  'tablet computer', 'rectangle', 'line', 'pattern', 'parallel', 'web page',
  'website', 'lecture', 'public speaking', 'seminar', 'conference',
  'plastic', 'stool', 'chair', 'household', 'floor', 'flooring',
  'carpet', 'rug', 'textile', 
  
};

/// Whether a photo shows people or scenery (so it belongs in the results when
/// the person chose "people and scenery only"). Unknown is kept: a photo is
/// only left out when the labeller was confident it shows a document, a
/// screen or an object and found no sign of people or scenery.
bool isPeopleOrScenery({
  required int? faceCount,
  required List<PhotoLabel>? labels,
  double strong = 0.6,
  double objectThreshold = 0.5,
}) {
  if (faceCount != null && faceCount > 0) return true;
  if (labels == null || labels.isEmpty) return true;
  double best(Set<String> names) {
    var top = 0.0;
    for (final label in labels) {
      if (names.contains(label.name.toLowerCase()) &&
          label.confidence > top) {
        top = label.confidence;
      }
    }
    return top;
  }

  // The subject decides: people or scenery only count when they are at least
  // about as certain as the screen, document or object in the picture. A
  // speaker seen far across a hall behind a big slide is a photo of the slide.
  final subject = math.max(best(peopleLabels), best(sceneryLabels));
  final thing = best(objectLabels);
  if (subject >= strong && subject >= thing - 0.15) return true;
  return thing < objectThreshold;
}
