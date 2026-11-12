#include <windows.h>
#include <vector>
static_assert(_MSC_VER == PROVDESK_EXPECTED_MSC_VER, "Unexpected MSVC compiler selected by MSBuild");
int main() {
    std::vector<int> values{1, 2};
    return GetCurrentProcessId() != 0 && values.size() == 2 ? 0 : 1;
}
