#pragma once
#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>
#include <stdint.h>

uint32_t SNBWindowID(AXUIElementRef window);
CFArrayRef SNBCopyWindowSpaces(uint32_t windowID) CF_RETURNS_RETAINED;
bool SNBCanMoveWindows(void);
// A true result means dispatched, not completed; callers must verify membership.
bool SNBMoveWindow(uint32_t windowID, uint64_t spaceID);
