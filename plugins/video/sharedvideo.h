#pragma once

// Kirin.Video: one video player for several outputs (kirin's video
// wallpaper on every monitor). The video is decoded once; every frame goes
// to each active feed, so all monitors show the same frame. A feed that
// isn't active keeps its last frame; with none active the player pauses.
//
//   SharedVideo { id: shared; source: "file:///…/video.mp4" }
//   VideoOutput { id: out }
//   VideoFeed { video: shared; output: out; active: true }

#include <QList>
#include <QMediaPlayer>
#include <QObject>
#include <QPointer>
#include <QUrl>
#include <QVideoFrame>
#include <QVideoSink>
#include <QtQml/qqmlregistration.h>

class VideoFeed;

class SharedVideo : public QObject {
	Q_OBJECT
	QML_ELEMENT

	// The video, played muted and looped.
	Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
	// Frames have come since the source was set.
	Q_PROPERTY(bool started READ started NOTIFY startedChanged)
	// Some feed takes frames, so the player plays.
	Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
	Q_PROPERTY(QString errorString READ errorString NOTIFY errorChanged)

public:
	explicit SharedVideo(QObject* parent = nullptr);

	[[nodiscard]] QUrl source() const;
	void setSource(const QUrl& source);
	[[nodiscard]] bool started() const;
	[[nodiscard]] bool playing() const;
	[[nodiscard]] QString errorString() const;

	[[nodiscard]] QVideoFrame lastFrame() const;
	void addFeed(VideoFeed* feed);
	void removeFeed(VideoFeed* feed);
	// A feed turned on or off: play while any is on.
	void updatePlaying();

signals:
	void sourceChanged();
	void startedChanged();
	void playingChanged();
	void errorChanged();

private:
	void onFrame(const QVideoFrame& frame);

	QMediaPlayer mPlayer;
	QVideoSink mSink;
	QVideoFrame mLastFrame;
	QList<QPointer<VideoFeed>> mFeeds;
	bool mStarted = false;
	bool mPlaying = false;
};

class VideoFeed : public QObject {
	Q_OBJECT
	QML_ELEMENT

	Q_PROPERTY(SharedVideo* video READ video WRITE setVideo NOTIFY videoChanged)
	// A VideoOutput (its videoSink gets the frames).
	Q_PROPERTY(QObject* output READ output WRITE setOutput NOTIFY outputChanged)
	// Taking frames; off, the output keeps its last one.
	Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)

public:
	explicit VideoFeed(QObject* parent = nullptr);
	~VideoFeed() override;

	[[nodiscard]] SharedVideo* video() const;
	void setVideo(SharedVideo* video);
	[[nodiscard]] QObject* output() const;
	void setOutput(QObject* output);
	[[nodiscard]] bool active() const;
	void setActive(bool active);

	// A frame from the video, shown if active.
	void deliver(const QVideoFrame& frame);

signals:
	void videoChanged();
	void outputChanged();
	void activeChanged();

private:
	[[nodiscard]] QVideoSink* sink() const;

	QPointer<SharedVideo> mVideo;
	QPointer<QObject> mOutput;
	// Off until turned on: QML sets `video` and `output` before `active`, and
	// a feed on by default handed out a frame it was about to be told not to.
	bool mActive = false;
};
