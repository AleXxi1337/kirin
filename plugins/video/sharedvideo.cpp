#include "sharedvideo.h"

#include <QVariant>

// --- SharedVideo ---------------------------------------------------------------

SharedVideo::SharedVideo(QObject* parent): QObject(parent) {
	// No audio output: muted.
	this->mPlayer.setVideoSink(&this->mSink);
	this->mPlayer.setLoops(QMediaPlayer::Infinite);

	QObject::connect(&this->mSink, &QVideoSink::videoFrameChanged, this, &SharedVideo::onFrame);
	QObject::connect(&this->mPlayer, &QMediaPlayer::errorChanged, this, &SharedVideo::errorChanged);
}

QUrl SharedVideo::source() const { return this->mPlayer.source(); }

void SharedVideo::setSource(const QUrl& source) {
	if (source == this->mPlayer.source()) return;

	this->mPlayer.setSource(source);
	// The old video's last frame isn't this one's: a feed joining before the
	// new one has a frame (paused, say) would show it.
	this->mLastFrame = QVideoFrame();
	if (this->mStarted) {
		this->mStarted = false;
		emit this->startedChanged();
	}
	emit this->sourceChanged();

	// Setting a source stops the player; start again if wanted.
	if (this->mPlaying && !source.isEmpty()) this->mPlayer.play();
}

bool SharedVideo::started() const { return this->mStarted; }
bool SharedVideo::playing() const { return this->mPlaying; }
QString SharedVideo::errorString() const { return this->mPlayer.errorString(); }
QVideoFrame SharedVideo::lastFrame() const { return this->mLastFrame; }

void SharedVideo::addFeed(VideoFeed* feed) {
	if (!this->mFeeds.contains(feed)) this->mFeeds.append(feed);
	this->updatePlaying();
}

void SharedVideo::removeFeed(VideoFeed* feed) {
	this->mFeeds.removeAll(feed);
	this->updatePlaying();
}

void SharedVideo::updatePlaying() {
	auto wanted = false;
	for (const auto& feed: this->mFeeds) {
		if (feed && feed->active()) {
			wanted = true;
			break;
		}
	}

	if (wanted == this->mPlaying) return;
	this->mPlaying = wanted;

	if (wanted) {
		if (!this->mPlayer.source().isEmpty()) this->mPlayer.play();
	} else {
		this->mPlayer.pause();
	}

	emit this->playingChanged();
}

void SharedVideo::onFrame(const QVideoFrame& frame) {
	if (!frame.isValid()) return;

	this->mLastFrame = frame;
	if (!this->mStarted) {
		this->mStarted = true;
		emit this->startedChanged();
	}

	for (const auto& feed: this->mFeeds) {
		if (feed) feed->deliver(frame);
	}
}

// --- VideoFeed -----------------------------------------------------------------

VideoFeed::VideoFeed(QObject* parent): QObject(parent) {}

VideoFeed::~VideoFeed() {
	if (this->mVideo) this->mVideo->removeFeed(this);
}

SharedVideo* VideoFeed::video() const { return this->mVideo; }

void VideoFeed::setVideo(SharedVideo* video) {
	if (video == this->mVideo) return;

	if (this->mVideo) this->mVideo->removeFeed(this);
	this->mVideo = video;
	if (video) {
		video->addFeed(this);
		// Show where it's at right away, not at the next frame.
		this->deliver(video->lastFrame());
	}

	emit this->videoChanged();
}

QObject* VideoFeed::output() const { return this->mOutput; }

void VideoFeed::setOutput(QObject* output) {
	if (output == this->mOutput) return;

	this->mOutput = output;
	if (this->mVideo) this->deliver(this->mVideo->lastFrame());

	emit this->outputChanged();
}

bool VideoFeed::active() const { return this->mActive; }

void VideoFeed::setActive(bool active) {
	if (active == this->mActive) return;

	this->mActive = active;
	if (this->mVideo) {
		this->mVideo->updatePlaying();
		// Back from its own pause: straight to the current frame.
		if (active) this->deliver(this->mVideo->lastFrame());
	}

	emit this->activeChanged();
}

void VideoFeed::deliver(const QVideoFrame& frame) {
	if (!this->mActive || !frame.isValid()) return;
	if (auto* sink = this->sink()) sink->setVideoFrame(frame);
}

QVideoSink* VideoFeed::sink() const {
	if (!this->mOutput) return nullptr;
	return this->mOutput->property("videoSink").value<QVideoSink*>();
}
