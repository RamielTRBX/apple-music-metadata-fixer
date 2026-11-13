ObjC.import("Foundation");

function readText(path) {
  return $.NSString
    .stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null)
    .js;
}

function writeText(path, text) {
  const value = $.NSString.stringWithString(text);
  if (
    !value.writeToFileAtomicallyEncodingError(
      path,
      true,
      $.NSUTF8StringEncoding,
      null
    )
  ) {
    throw new Error("Could not write " + path);
  }
}

function run(argv) {
  const request = JSON.parse(readText(argv[0]));
  const outputPath = argv[1];
  const music = Application("Music");
  const fields = [
    "name",
    "sortName",
    "album",
    "sortAlbum",
    "artist",
    "sortArtist",
    "albumArtist",
    "sortAlbumArtist"
  ];
  let updated = 0;
  const missing = [];

  for (const update of request.updates || []) {
    const persistentID = String(update.persistentID);
    const matches = music.tracks.whose({ persistentID })();
    if (!matches.length) {
      missing.push(persistentID);
      continue;
    }
    const track = matches[0];
    for (const field of fields) {
      if (Object.prototype.hasOwnProperty.call(update, field)) {
        track[field] = update[field];
      }
    }
    updated += 1;
  }

  writeText(outputPath, JSON.stringify({ updated, missing }));
  return String(updated);
}
