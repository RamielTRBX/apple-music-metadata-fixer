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
  const tracks = music.tracks();
  const count = tracks.length;

  const dates = music.tracks.dateAdded();
  const persistentIDs = music.tracks.persistentID();
  const databaseIDs = music.tracks.databaseID();
  const names = music.tracks.name();
  const artists = music.tracks.artist();
  const albumArtists = music.tracks.albumArtist();
  const albums = music.tracks.album();
  const genres = music.tracks.genre();
  const discNumbers = music.tracks.discNumber();
  const discCounts = music.tracks.discCount();
  const trackNumbers = music.tracks.trackNumber();
  const trackCounts = music.tracks.trackCount();
  const durations = music.tracks.duration();

  const lengths = [
    dates.length,
    persistentIDs.length,
    databaseIDs.length,
    names.length,
    artists.length,
    albumArtists.length,
    albums.length,
    genres.length,
    discNumbers.length,
    discCounts.length,
    trackNumbers.length,
    trackCounts.length,
    durations.length
  ];
  if (lengths.some((length) => length !== count)) {
    throw new Error("Apple Music changed while its metadata was being read.");
  }

  const pending = new Set(
    (request.pendingPersistentIDs || []).map((value) => String(value))
  );
  const cutoff = Number(request.since);
  const rows = [];

  for (let index = 0; index < count; index += 1) {
    const persistentID = String(persistentIDs[index]);
    const added = new Date(dates[index]).getTime();
    if (added < cutoff && !pending.has(persistentID)) {
      continue;
    }
    let artworkHexPath = null;
    try {
      const artworks = tracks[index].artworks();
      if (artworks.length > 0) {
        const raw = ObjC.unwrap(artworks[0].rawData());
        artworkHexPath = `${request.artworkDirectory}/${persistentID}.hex`;
        writeText(artworkHexPath, String(raw));
      }
    } catch {}
    rows.push({
      persistentID,
      databaseID: Number(databaseIDs[index]),
      name: String(names[index] || ""),
      artist: String(artists[index] || ""),
      albumArtist: String(albumArtists[index] || ""),
      album: String(albums[index] || ""),
      genre: String(genres[index] || ""),
      discNumber: Number(discNumbers[index] || 1),
      discCount: Number(discCounts[index] || 1),
      trackNumber: Number(trackNumbers[index] || 0),
      trackCount: Number(trackCounts[index] || 0),
      duration: Number(durations[index] || 0),
      dateAdded: added,
      artworkHexPath
    });
  }

  writeText(outputPath, JSON.stringify(rows));
  return String(rows.length);
}
