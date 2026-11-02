// Stand-in for Apple's private IOHIDLibPrivate.h: only the logging macros the
// acceleration sources use, compiled out.
#pragma once
#define HIDLogDebug(...) do {} while (0)
#define HIDLogInfo(...) do {} while (0)
#define HIDLog(...) do {} while (0)
#define HIDLogError(...) do {} while (0)
