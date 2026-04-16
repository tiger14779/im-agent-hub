cmake_minimum_required(VERSION 3.16)

project(im-agent-hub-pc VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.7 REQUIRED COMPONENTS
    Quick
    QuickControls2
    Network
    WebSockets
    Multimedia
    Sql
)

qt_standard_project_setup(REQUIRES 6.7)

# ── Sources ──────────────────────────────────────────────
set(SOURCES
    src/main.cpp
    src/models/chatmodel.cpp
    src/models/contactmodel.cpp
    src/network/httpclient.cpp
    src/network/wsclient.cpp
    src/network/wxbridge.cpp
    src/network/audiocallengine.cpp
    src/database/messagecache.cpp
)

set(HEADERS
    src/models/chatmodel.h
    src/models/contactmodel.h
    src/network/httpclient.h
    src/network/wsclient.h
    src/network/wxbridge.h
    src/network/audiocallengine.h
    src/database/messagecache.h
)

# ── QML files ────────────────────────────────────────────
set(QML_FILES
    qml/Main.qml
    qml/LoginPage.qml
    qml/ChatPage.qml
    qml/components/ContactList.qml
    qml/components/GroupInfoDrawer.qml
    qml/components/InviteMemberDialog.qml
    qml/components/MessageList.qml
    qml/components/ChatInput.qml
    qml/components/MessageBubble.qml
    qml/components/ImageViewer.qml
    qml/components/VoiceCallWindow.qml
)

qt_add_executable(${PROJECT_NAME}
    ${SOURCES}
    ${HEADERS}
)

# Windows 下隐藏控制台窗口（仅 Release 生效）
set_target_properties(${PROJECT_NAME} PROPERTIES
    WIN32_EXECUTABLE $<NOT:$<CONFIG:Debug>>
)

qt_add_qml_module(${PROJECT_NAME}
    URI ImAgentHub
    VERSION 1.0
    QML_FILES ${QML_FILES}
    RESOURCES
        resources/notify.wav
    RESOURCE_PREFIX /
)

target_link_libraries(${PROJECT_NAME} PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Network
    Qt6::WebSockets
    Qt6::Multimedia
    Qt6::Sql
)

target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/models
    ${CMAKE_CURRENT_SOURCE_DIR}/src/network
    ${CMAKE_CURRENT_SOURCE_DIR}/src/database
)

# Pass Qt QML import path so the app can find QtMultimedia etc. at runtime
# Qt6_DIR = <qt>/lib/cmake/Qt6, so go up 3 levels to get <qt>, then append /qml
cmake_path(GET Qt6_DIR PARENT_PATH _cmake_dir)
cmake_path(GET _cmake_dir PARENT_PATH _lib_dir)
cmake_path(GET _lib_dir PARENT_PATH _qt6_root)
set(_qt6_qml_import_dir "${_qt6_root}/qml")
message(STATUS "Qt6 QML import dir: ${_qt6_qml_import_dir}")
target_compile_definitions(${PROJECT_NAME} PRIVATE
    "QT_QML_IMPORT_DIR=\"${_qt6_qml_import_dir}\""
)

# Windows specific (disabled for debug console output)
# if(WIN32)
#     set_target_properties(${PROJECT_NAME} PROPERTIES
#         WIN32_EXECUTABLE TRUE
#     )
# endif()

# Install
install(TARGETS ${PROJECT_NAME}
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
