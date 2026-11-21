cmake_minimum_required(VERSION 3.27)
project(kirin-bars VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(deps REQUIRED IMPORTED_TARGET hyprland pixman-1 libdrm libinput libudev wayland-server xkbcommon pangocairo)

add_library(kirin-bars MODULE src/main.cpp src/barDeco.cpp src/BarPassElement.cpp)
set_target_properties(kirin-bars PROPERTIES PREFIX "")
target_link_libraries(kirin-bars PRIVATE PkgConfig::deps)
target_compile_options(kirin-bars PRIVATE -Wno-narrowing)
if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    target_compile_options(kirin-bars PRIVATE -fno-gnu-unique)
endif()

install(TARGETS kirin-bars LIBRARY DESTINATION lib)
