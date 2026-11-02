/*
 * hk-dispatch-bench: what a compute dispatch costs on the Vulkan driver, and
 * whether dispatches are still ordered where Vulkan says they must be.
 *
 * The same shape as tools/metal-probe/dispatch on macOS: 4096 dispatches of
 * 4096 threads, independent (no barriers) and dependent (a pipeline barrier
 * between each). Then three checks a driver that drops a barrier would fail:
 *
 *   dependent  4096 increments through barriers add up to 4096 exactly
 *   distinct   4096 unordered dispatches to separate slots all land
 *   chain      4096 dispatches each reading the last one's result, with a
 *              barrier between, end on 4096
 *
 * Exits non-zero if a check fails.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vulkan/vulkan.h>

#include "bench.spv.h"

#define SLOT    4096 /* words a dispatch touches: 16 groups of 256 */
#define N       4096 /* dispatches per test */
#define REPEATS 5

#define CHECK(x)                                                               \
   do {                                                                        \
      VkResult r_ = (x);                                                       \
      if (r_ != VK_SUCCESS) {                                                  \
         fprintf(stderr, "%s:%d: %s failed (%d)\n", __FILE__, __LINE__, #x,    \
                 r_);                                                          \
         exit(2);                                                              \
      }                                                                        \
   } while (0)

struct params {
   uint32_t mode, dst, src, val;
};

enum { ADD, FILL, STEP };

static VkDevice dev;
static VkQueue queue;
static VkCommandBuffer cb;
static VkFence fence;
static VkPipeline pipe;
static VkPipelineLayout layout;
static VkDescriptorSet set;
static VkQueryPool queries;
static bool timestamps;
static double ns_per_tick;
static uint32_t *words;

static double
now_ns(void)
{
   struct timespec t;
   clock_gettime(CLOCK_MONOTONIC, &t);
   return t.tv_sec * 1e9 + t.tv_nsec;
}

static void
dispatch(uint32_t mode, uint32_t dst, uint32_t src, uint32_t val)
{
   struct params p = {mode, dst * SLOT, src * SLOT, val};
   vkCmdPushConstants(cb, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(p),
                      &p);
   vkCmdDispatch(cb, SLOT / 256, 1, 1);
}

static void
barrier(void)
{
   VkMemoryBarrier b = {
      .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
      .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT,
      .dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT,
   };
   vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                        VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 1, &b, 0, NULL,
                        0, NULL);
}

/* Records body() between two timestamps, runs it, and returns the time per
 * dispatch in microseconds: GPU time where the queue has timestamps, wall
 * time from submit to fence otherwise. */
static double
run(void (*body)(void), bool *gpu_time)
{
   VkCommandBufferBeginInfo begin = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
   };
   CHECK(vkResetCommandBuffer(cb, 0));
   CHECK(vkBeginCommandBuffer(cb, &begin));
   if (timestamps) {
      vkCmdResetQueryPool(cb, queries, 0, 2);
      vkCmdWriteTimestamp(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, queries, 0);
   }
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipe);
   vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1,
                           &set, 0, NULL);
   body();
   if (timestamps)
      vkCmdWriteTimestamp(cb, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, queries, 1);
   CHECK(vkEndCommandBuffer(cb));

   VkSubmitInfo submit = {
      .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
      .commandBufferCount = 1,
      .pCommandBuffers = &cb,
   };
   CHECK(vkResetFences(dev, 1, &fence));
   double t0 = now_ns();
   CHECK(vkQueueSubmit(queue, 1, &submit, fence));
   CHECK(vkWaitForFences(dev, 1, &fence, VK_TRUE, UINT64_MAX));
   double wall = now_ns() - t0;

   *gpu_time = false;
   if (timestamps) {
      uint64_t t[2];
      if (vkGetQueryPoolResults(dev, queries, 0, 2, sizeof(t), t,
                                sizeof(t[0]), VK_QUERY_RESULT_64_BIT |
                                                 VK_QUERY_RESULT_WAIT_BIT) ==
             VK_SUCCESS &&
          t[1] > t[0]) {
         *gpu_time = true;
         return (t[1] - t[0]) * ns_per_tick / N / 1e3;
      }
   }
   return wall / N / 1e3;
}

static void
independent(void)
{
   for (uint32_t k = 0; k < N; k++)
      dispatch(ADD, 0, 0, 0);
}

static void
dependent(void)
{
   for (uint32_t k = 0; k < N; k++) {
      if (k)
         barrier();
      dispatch(ADD, 0, 0, 0);
   }
}

static void
distinct(void)
{
   for (uint32_t k = 0; k < N; k++)
      dispatch(FILL, k, 0, k + 1);
}

static void
chain(void)
{
   dispatch(FILL, 0, 0, 0);
   for (uint32_t k = 1; k <= N; k++) {
      barrier();
      dispatch(STEP, k % 2, (k - 1) % 2, 0);
   }
}

static double
best_of(void (*body)(void), bool *gpu_time)
{
   double best = 1e30;
   for (int r = 0; r < REPEATS; r++) {
      memset(words, 0, (size_t)(N + 2) * SLOT * 4);
      double t = run(body, gpu_time);
      if (t < best)
         best = t;
   }
   return best;
}

static bool
expect(const char *name, uint32_t slot, uint32_t (*want)(uint32_t))
{
   for (uint32_t s = 0; s < (slot == UINT32_MAX ? N : 1); s++) {
      uint32_t at = slot == UINT32_MAX ? s : slot;
      for (uint32_t i = 0; i < SLOT; i++) {
         uint32_t got = words[at * SLOT + i];
         if (got != want(at)) {
            printf("  %-11s FAIL: slot %u word %u is %u, expected %u\n", name,
                   at, i, got, want(at));
            return false;
         }
      }
   }
   printf("  %-11s ok\n", name);
   return true;
}

/* Whether the instance (pdev NULL) or the device offers an extension. */
static bool
has_extension(VkPhysicalDevice pdev, const char *name)
{
   uint32_t count = 0;
   if (pdev)
      vkEnumerateDeviceExtensionProperties(pdev, NULL, &count, NULL);
   else
      vkEnumerateInstanceExtensionProperties(NULL, &count, NULL);

   VkExtensionProperties *exts = calloc(count, sizeof(*exts));
   if (pdev)
      vkEnumerateDeviceExtensionProperties(pdev, NULL, &count, exts);
   else
      vkEnumerateInstanceExtensionProperties(NULL, &count, exts);

   bool found = false;
   for (uint32_t i = 0; i < count; i++)
      found |= !strcmp(exts[i].extensionName, name);
   free(exts);
   return found;
}

static uint32_t want_n(uint32_t s) { (void)s; return N; }
static uint32_t want_slot(uint32_t s) { return s + 1; }

int
main(void)
{
   VkApplicationInfo app = {
      .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
      .pApplicationName = "hk-dispatch-bench",
      .apiVersion = VK_API_VERSION_1_1,
   };
   /* Portability drivers (MoltenVK, for a Metal reference on macOS) are only
    * listed for applications that ask. */
   const char *portability = "VK_KHR_portability_enumeration";
   bool has_portability = has_extension(NULL, portability);
   VkInstanceCreateInfo ici = {
      .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
      .flags = has_portability
                  ? VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR
                  : 0,
      .pApplicationInfo = &app,
      .enabledExtensionCount = has_portability,
      .ppEnabledExtensionNames = &portability,
   };
   VkInstance inst;
   CHECK(vkCreateInstance(&ici, NULL, &inst));

   uint32_t count = 0;
   CHECK(vkEnumeratePhysicalDevices(inst, &count, NULL));
   if (!count) {
      fprintf(stderr, "no Vulkan device\n");
      return 2;
   }
   VkPhysicalDevice *pdevs = calloc(count, sizeof(*pdevs));
   CHECK(vkEnumeratePhysicalDevices(inst, &count, pdevs));
   VkPhysicalDevice pdev = pdevs[0];

   VkPhysicalDeviceDriverProperties driver = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES,
   };
   VkPhysicalDeviceProperties2 props = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
      .pNext = &driver,
   };
   vkGetPhysicalDeviceProperties2(pdev, &props);
   printf("%s, %s %s\n", props.properties.deviceName, driver.driverName,
          driver.driverInfo);

   uint32_t qcount = 0;
   vkGetPhysicalDeviceQueueFamilyProperties(pdev, &qcount, NULL);
   VkQueueFamilyProperties *qprops = calloc(qcount, sizeof(*qprops));
   vkGetPhysicalDeviceQueueFamilyProperties(pdev, &qcount, qprops);
   uint32_t qf = UINT32_MAX;
   for (uint32_t i = 0; i < qcount; i++) {
      if (qprops[i].queueFlags & VK_QUEUE_COMPUTE_BIT) {
         qf = i;
         break;
      }
   }
   if (qf == UINT32_MAX) {
      fprintf(stderr, "no compute queue\n");
      return 2;
   }
   timestamps = qprops[qf].timestampValidBits > 0;
   ns_per_tick = props.properties.limits.timestampPeriod;

   float prio = 1.0f;
   VkDeviceQueueCreateInfo qci = {
      .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex = qf,
      .queueCount = 1,
      .pQueuePriorities = &prio,
   };
   const char *subset = "VK_KHR_portability_subset";
   bool has_subset = has_extension(pdev, subset);
   VkDeviceCreateInfo dci = {
      .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
      .queueCreateInfoCount = 1,
      .pQueueCreateInfos = &qci,
      .enabledExtensionCount = has_subset,
      .ppEnabledExtensionNames = &subset,
   };
   CHECK(vkCreateDevice(pdev, &dci, NULL, &dev));
   vkGetDeviceQueue(dev, qf, 0, &queue);

   /* One host-visible buffer: N slots plus two for the chain. */
   VkDeviceSize size = (VkDeviceSize)(N + 2) * SLOT * 4;
   VkBufferCreateInfo bci = {
      .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
      .size = size,
      .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
   };
   VkBuffer buf;
   CHECK(vkCreateBuffer(dev, &bci, NULL, &buf));
   VkMemoryRequirements req;
   vkGetBufferMemoryRequirements(dev, buf, &req);
   VkPhysicalDeviceMemoryProperties mem;
   vkGetPhysicalDeviceMemoryProperties(pdev, &mem);
   const VkMemoryPropertyFlags want = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                                      VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
   uint32_t type = UINT32_MAX;
   for (uint32_t i = 0; i < mem.memoryTypeCount; i++) {
      if ((req.memoryTypeBits & (1u << i)) &&
          (mem.memoryTypes[i].propertyFlags & want) == want) {
         type = i;
         break;
      }
   }
   if (type == UINT32_MAX) {
      fprintf(stderr, "no host-visible coherent memory\n");
      return 2;
   }
   VkMemoryAllocateInfo mai = {
      .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize = req.size,
      .memoryTypeIndex = type,
   };
   VkDeviceMemory memory;
   CHECK(vkAllocateMemory(dev, &mai, NULL, &memory));
   CHECK(vkBindBufferMemory(dev, buf, memory, 0));
   CHECK(vkMapMemory(dev, memory, 0, size, 0, (void **)&words));

   VkDescriptorSetLayoutBinding binding = {
      .binding = 0,
      .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
      .descriptorCount = 1,
      .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
   };
   VkDescriptorSetLayoutCreateInfo dslci = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .bindingCount = 1,
      .pBindings = &binding,
   };
   VkDescriptorSetLayout dsl;
   CHECK(vkCreateDescriptorSetLayout(dev, &dslci, NULL, &dsl));
   VkPushConstantRange range = {VK_SHADER_STAGE_COMPUTE_BIT, 0,
                                sizeof(struct params)};
   VkPipelineLayoutCreateInfo plci = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      .setLayoutCount = 1,
      .pSetLayouts = &dsl,
      .pushConstantRangeCount = 1,
      .pPushConstantRanges = &range,
   };
   CHECK(vkCreatePipelineLayout(dev, &plci, NULL, &layout));

   VkDescriptorPoolSize psize = {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1};
   VkDescriptorPoolCreateInfo dpci = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
      .maxSets = 1,
      .poolSizeCount = 1,
      .pPoolSizes = &psize,
   };
   VkDescriptorPool dpool;
   CHECK(vkCreateDescriptorPool(dev, &dpci, NULL, &dpool));
   VkDescriptorSetAllocateInfo dsai = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
      .descriptorPool = dpool,
      .descriptorSetCount = 1,
      .pSetLayouts = &dsl,
   };
   CHECK(vkAllocateDescriptorSets(dev, &dsai, &set));
   VkDescriptorBufferInfo dbi = {buf, 0, VK_WHOLE_SIZE};
   VkWriteDescriptorSet wds = {
      .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      .dstSet = set,
      .descriptorCount = 1,
      .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
      .pBufferInfo = &dbi,
   };
   vkUpdateDescriptorSets(dev, 1, &wds, 0, NULL);

   VkShaderModuleCreateInfo smci = {
      .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize = sizeof(bench_spv),
      .pCode = bench_spv,
   };
   VkShaderModule module;
   CHECK(vkCreateShaderModule(dev, &smci, NULL, &module));
   VkComputePipelineCreateInfo cpci = {
      .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage =
         {
            .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VK_SHADER_STAGE_COMPUTE_BIT,
            .module = module,
            .pName = "main",
         },
      .layout = layout,
   };
   CHECK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cpci, NULL, &pipe));

   VkCommandPoolCreateInfo cpi = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
      .queueFamilyIndex = qf,
   };
   VkCommandPool cpool;
   CHECK(vkCreateCommandPool(dev, &cpi, NULL, &cpool));
   VkCommandBufferAllocateInfo cbai = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool = cpool,
      .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
      .commandBufferCount = 1,
   };
   CHECK(vkAllocateCommandBuffers(dev, &cbai, &cb));
   VkFenceCreateInfo fci = {.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
   CHECK(vkCreateFence(dev, &fci, NULL, &fence));
   if (timestamps) {
      VkQueryPoolCreateInfo qpci = {
         .sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
         .queryType = VK_QUERY_TYPE_TIMESTAMP,
         .queryCount = 2,
      };
      CHECK(vkCreateQueryPool(dev, &qpci, NULL, &queries));
   }

   bool gpu;
   double t;
   printf("%d dispatches of %d threads, best of %d:\n", N, SLOT, REPEATS);
   t = best_of(independent, &gpu);
   printf("  independent %.2f us each (%s)\n", t, gpu ? "GPU" : "wall");
   t = best_of(dependent, &gpu);
   printf("  dependent   %.2f us each (%s)\n", t, gpu ? "GPU" : "wall");

   printf("ordering:\n");
   bool ok = true;
   memset(words, 0, size);
   run(dependent, &gpu);
   ok &= expect("dependent", 0, want_n);
   memset(words, 0, size);
   run(distinct, &gpu);
   ok &= expect("distinct", UINT32_MAX, want_slot);
   memset(words, 0, size);
   run(chain, &gpu);
   ok &= expect("chain", N % 2, want_n);

   return ok ? 0 : 1;
}
