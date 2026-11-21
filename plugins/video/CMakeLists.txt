cmake_minimum_required(VERSION 3.21)
project(kirin-video VERSION 0.1.0 LANGUAGES CXX)

# Kirin.Video: a QML module for Quickshell (kirin's video wallpapers). Build
# it against the same Qt as Quickshell, and put the installed
# lib/qt-6/qml on QML_IMPORT_PATH (or install it into Qt's qml directory).
#
#   cmake -B build -DCMAKE_INSTALL_PREFIX=/usr && cmake --build build && cmake --install build

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Qml Multimedia)
qt_standard_project_setup(REQUIRES 6.5)

# Where the module goes, under the prefix: Qt's layout on NixOS and
# Arch-likes alike when the prefix is Qt's; override if yours differs.
set(KIRIN_QML_DIR "lib/qt-6/qml" CACHE STRING "QML import directory, relative to the install prefix")

qt_add_qml_module(kirinvideo
	URI Kirin.Video
	VERSION 1.0
	PLUGIN_TARGET kirinvideo
	OUTPUT_DIRECTORY Kirin/Video
	SOURCES sharedvideo.h sharedvideo.cpp
)

target_link_libraries(kirinvideo PRIVATE Qt6::Core Qt6::Qml Qt6::Multimedia)

install(TARGETS kirinvideo LIBRARY DESTINATION "${KIRIN_QML_DIR}/Kirin/Video")
install(
	DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/Kirin/Video/"
	DESTINATION "${KIRIN_QML_DIR}/Kirin/Video"
	FILES_MATCHING PATTERN "qmldir" PATTERN "*.qmltypes"
)
