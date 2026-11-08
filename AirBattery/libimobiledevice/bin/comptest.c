// Apple Watch battery reader for AirBattery.
// Protocol reference: https://gist.github.com/nikias/ebc6e975dc908f3741af0f789c5b1088
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/companion_proxy.h>
#include <plist/plist.h>

static plist_t read_value(idevice_t device, const char *udid, const char *key)
{
    companion_proxy_client_t client = NULL;
    plist_t response = NULL;
    plist_t value = NULL;
    companion_proxy_error_t error = companion_proxy_client_start_service(device, &client, "AirBattery");
    if (error == COMPANION_PROXY_E_SUCCESS && client) {
        error = companion_proxy_get_value_from_registry(client, udid, key, &response);
        if (error == COMPANION_PROXY_E_SUCCESS && response) {
            plist_t node = plist_dict_get_item(response, key);
            if (node) value = plist_copy(node);
        }
    }
    if (!value) fprintf(stderr, "Watch field unavailable: %s (%d)\n", key, error);
    if (response) plist_free(response);
    if (client) companion_proxy_client_free(client);
    return value;
}

int main(int argc, char **argv)
{
    if (argc != 2 || !argv[1][0]) {
        fprintf(stderr, "Usage: comptest UDID\n");
        return 2;
    }
    // Termination uses the OS default: no library calls from signal handlers.
    signal(SIGPIPE, SIG_IGN);
    alarm(14);
    idevice_t device = NULL;
    if (idevice_new_with_options(&device, argv[1], IDEVICE_LOOKUP_USBMUX | IDEVICE_LOOKUP_NETWORK) != IDEVICE_E_SUCCESS || !device) {
        fprintf(stderr, "Phone unavailable\n");
        return 1;
    }
    companion_proxy_client_t client = NULL;
    plist_t registry = NULL;
    companion_proxy_error_t error = companion_proxy_client_start_service(device, &client, "AirBattery");
    if (error == COMPANION_PROXY_E_SUCCESS && client) {
        error = companion_proxy_get_device_registry(client, &registry);
    }
    if (client) companion_proxy_client_free(client);
    int status = 0;
    if (error != COMPANION_PROXY_E_SUCCESS || !registry || plist_get_node_type(registry) != PLIST_ARRAY) {
        fprintf(stderr, "Watch registry unavailable (%d)\n", error);
        status = error == COMPANION_PROXY_E_NO_DEVICES ? 0 : 1;
    } else {
        for (uint32_t i = 0; i < plist_array_get_size(registry); i++) {
            char *udid = NULL;
            plist_t entry = plist_array_get_item(registry, i);
            if (plist_get_node_type(entry) != PLIST_STRING) continue;
            plist_get_string_val(entry, &udid);
            if (!udid || !udid[0]) { free(udid); continue; }
            const char *keys[] = {"DeviceName", "ProductType", "BatteryCurrentCapacity", "BatteryIsCharging"};
            plist_t values[4] = {NULL, NULL, NULL, NULL};
            for (int k = 0; k < 4; k++) values[k] = read_value(device, udid, keys[k]);
            if (values[0] && plist_get_node_type(values[0]) == PLIST_STRING &&
                values[1] && plist_get_node_type(values[1]) == PLIST_STRING &&
                values[2] && plist_get_node_type(values[2]) == PLIST_UINT &&
                values[3] && plist_get_node_type(values[3]) == PLIST_BOOLEAN) {
                char *name = NULL, *model = NULL;
                uint64_t level = 0;
                uint8_t charging = 0;
                plist_get_string_val(values[0], &name);
                plist_get_string_val(values[1], &model);
                plist_get_uint_val(values[2], &level);
                plist_get_bool_val(values[3], &charging);
                if (name && name[0] && model && model[0] && level <= 100) {
                    printf("Checking watch %s\nDeviceName: %s\nProductType: %s\nBatteryCurrentCapacity: %llu\nBatteryIsCharging: %s\n",
                           udid, name, model, (unsigned long long)level, charging ? "true" : "false");
                    fflush(stdout);
                } else status = 1;
                free(name);
                free(model);
            } else status = 1;
            for (int k = 0; k < 4; k++) if (values[k]) plist_free(values[k]);
            free(udid);
        }
    }
    if (registry) plist_free(registry);
    idevice_free(device);
    return status;
}
