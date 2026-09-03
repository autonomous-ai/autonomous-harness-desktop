/// The media capability ids a grid node can advertise.
///
/// Copied from Grid's `infrastructure/api/models/media_event.dart`, which is
/// most of a media pipeline this app has no use for — these three strings are
/// the whole of what the node and model panels need from it, so they are here
/// rather than dragging that file across.
library;

const String kCapImageGenerate = 'comfyui:image_generation';
const String kCapImageEdit = 'comfyui:image_editing';
const String kCapI2V = 'comfyui:i2v';
