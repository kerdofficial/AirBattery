#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/companion_proxy.h>

static const char *scenario;
static int clients;
idevice_error_t idevice_new_with_options(idevice_t *device, const char *udid, enum idevice_options options)
{
    (void)udid; (void)options;
    scenario = getenv("WATCH_SCENARIO");
    if (!scenario) scenario = "success";
    if (!strcmp(scenario, "blocked")) {
        fprintf(stderr, "ready\n");
        fflush(stderr);
        for (;;) pause();
    }
    if (!strcmp(scenario, "disconnected")) return IDEVICE_E_NO_DEVICE;
    *device = calloc(1, 1);
    return IDEVICE_E_SUCCESS;
}
idevice_error_t idevice_free(idevice_t device)
{
    assert(clients == 0);
    free(device);
    return IDEVICE_E_SUCCESS;
}
companion_proxy_error_t companion_proxy_client_start_service(idevice_t device, companion_proxy_client_t *client, const char *label)
{
    (void)device; (void)label;
    if (!strcmp(scenario, "service-failed")) return COMPANION_PROXY_E_UNKNOWN_ERROR;
    *client = calloc(1, 1);
    clients++;
    return COMPANION_PROXY_E_SUCCESS;
}
companion_proxy_error_t companion_proxy_client_free(companion_proxy_client_t client)
{
    assert(client);
    clients--;
    free(client);
    return COMPANION_PROXY_E_SUCCESS;
}
companion_proxy_error_t companion_proxy_get_device_registry(companion_proxy_client_t client, plist_t *registry)
{
    (void)client;
    if (!strcmp(scenario, "registry-failed")) return COMPANION_PROXY_E_UNKNOWN_ERROR;
    *registry = plist_new_array();
    if (strcmp(scenario, "no-watches")) plist_array_append_item(*registry, plist_new_string("watch-one-full-id"));
    return COMPANION_PROXY_E_SUCCESS;
}
companion_proxy_error_t companion_proxy_get_value_from_registry(companion_proxy_client_t client, const char *udid, const char *key, plist_t *value)
{
    (void)client; (void)udid;
    if (!strcmp(scenario, "missing-name") && !strcmp(key, "DeviceName")) return COMPANION_PROXY_E_UNSUPPORTED_KEY;
    *value = plist_new_dict();
    plist_t node;
    if (!strcmp(key, "DeviceName")) node = plist_new_string("Test Watch");
    else if (!strcmp(key, "ProductType")) node = plist_new_string("Watch7,1");
    else if (!strcmp(key, "BatteryCurrentCapacity")) node = plist_new_uint(!strcmp(scenario, "invalid-level") ? 101 : 42);
    else node = plist_new_bool(1);
    plist_dict_set_item(*value, key, node);
    return COMPANION_PROXY_E_SUCCESS;
}
