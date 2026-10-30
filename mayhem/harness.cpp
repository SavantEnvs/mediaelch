// One libFuzzer harness, compiled once per parser (-DFUZZ_KIND=<n>, see fuzz_targets.cmake).
// Every input comes from the fuzzer; nothing touches the filesystem.
#include <QByteArray>
#include <QCoreApplication>
#include <QDomDocument>
#include <QDomElement>
#include <QString>
#include <QXmlStreamReader>

#include <memory>
#include <vector>

#include "data/concert/Concert.h"
#include "data/movie/Movie.h"
#include "data/music/Album.h"
#include "data/music/Artist.h"
#include "data/tv_show/TvShow.h"
#include "data/tv_show/TvShowEpisode.h"
#include "media_center/kodi/AlbumXmlReader.h"
#include "media_center/kodi/ArtistXmlReader.h"
#include "media_center/kodi/ConcertXmlReader.h"
#include "media_center/kodi/EpisodeXmlReader.h"
#include "media_center/kodi/MovieXmlReader.h"
#include "media_center/kodi/TvShowXmlReader.h"
#include "renamer/PlaceholderParser.h"
#include "settings/AdvancedSettingsXmlReader.h"
#include "utils/Meta.h"

#define KIND_MOVIE 1
#define KIND_TVSHOW 2
#define KIND_EPISODE 3
#define KIND_CONCERT 4
#define KIND_ALBUM 5
#define KIND_ARTIST 6
#define KIND_ADVANCED_SETTINGS 7
#define KIND_PLACEHOLDER 8

#ifndef FUZZ_KIND
#error "FUZZ_KIND must be defined"
#endif

extern "C" int LLVMFuzzerInitialize(int* /*argc*/, char*** /*argv*/)
{
    static int argc = 1;
    static char name[] = "mediaelch-fuzz";
    static char* argv[] = {name, nullptr};
    static QCoreApplication app(argc, argv);
    registerAllMetaTypes();
    return 0;
}

[[maybe_unused]] static bool parseDom(const uint8_t* data, size_t size, QDomDocument& doc)
{
    const QByteArray bytes(reinterpret_cast<const char*>(data), static_cast<int>(size));
    return static_cast<bool>(doc.setContent(bytes));
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
    if (size > (1U << 20)) {
        return -1;
    }

#if FUZZ_KIND == KIND_MOVIE
    QDomDocument doc;
    if (!parseDom(data, size, doc)) {
        return -1;
    }
    Movie movie;
    mediaelch::kodi::MovieXmlReader reader(movie);
    (void) reader.parseNfoDom(doc);

#elif FUZZ_KIND == KIND_TVSHOW
    QDomDocument doc;
    if (!parseDom(data, size, doc)) {
        return -1;
    }
    TvShow show;
    mediaelch::kodi::TvShowXmlReader reader(show);
    (void) reader.parseNfoDom(doc);

#elif FUZZ_KIND == KIND_EPISODE
    QDomDocument doc;
    if (!parseDom(data, size, doc)) {
        return -1;
    }
    const QDomNodeList detailTags = doc.elementsByTagName("episodedetails");
    for (int i = 0; i < detailTags.size(); ++i) {
        TvShowEpisode episode;
        mediaelch::kodi::EpisodeXmlReader reader(episode);
        (void) reader.parseNfoDom(detailTags.at(i).toElement());
    }

#elif FUZZ_KIND == KIND_CONCERT
    const QByteArray bytes(reinterpret_cast<const char*>(data), static_cast<int>(size));
    Concert concert;
    mediaelch::kodi::ConcertXmlReader reader(concert);
    QXmlStreamReader stream(bytes);
    reader.parse(stream);
    if (stream.hasError()) {
        return -1;
    }

#elif FUZZ_KIND == KIND_ALBUM
    QDomDocument doc;
    if (!parseDom(data, size, doc)) {
        return -1;
    }
    Album album;
    mediaelch::kodi::AlbumXmlReader reader(album);
    (void) reader.parseNfoDom(doc);

#elif FUZZ_KIND == KIND_ARTIST
    QDomDocument doc;
    if (!parseDom(data, size, doc)) {
        return -1;
    }
    Artist artist;
    mediaelch::kodi::ArtistXmlReader reader(artist);
    (void) reader.parseNfoDom(doc);

#elif FUZZ_KIND == KIND_ADVANCED_SETTINGS
    const QString xml = QString::fromUtf8(reinterpret_cast<const char*>(data), static_cast<int>(size));
    (void) AdvancedSettingsXmlReader::loadFromXml(xml);

#elif FUZZ_KIND == KIND_PLACEHOLDER
    const QString input = QString::fromUtf8(reinterpret_cast<const char*>(data), static_cast<int>(size));
    const auto result = mediaelch::PlaceholderParser::parse(input);
    if (result.hasError()) {
        return -1;
    }

#else
#error "unknown FUZZ_KIND"
#endif
    return 0;
}
