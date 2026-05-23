import { CliError } from "./errors.js";
import { buildApplyPlan, createRenderContext, resolveApplyInputs } from "./apply.js";
import { renderManifestFiles } from "./render.js";
import type { GenerateOptions, GenerateReport, GeneratedFilePreview } from "./types.js";

export function generateDayuContent(options: GenerateOptions = {}): GenerateReport {
  const inputs = resolveApplyInputs(options);
  const plan = buildApplyPlan({ ...options, dryRun: true });
  const selectedOrder = options.capabilityId
    ? plan.deploymentOrder.filter((capabilityId) => capabilityId === options.capabilityId)
    : plan.deploymentOrder;

  if (options.capabilityId && selectedOrder.length === 0) {
    throw new CliError("unknown-capability", `capability '${options.capabilityId}' is not in the deployment plan`);
  }

  const context = createRenderContext(plan.targetRoot, inputs.config, inputs.registry);
  const files: GeneratedFilePreview[] = [];

  for (const capabilityId of selectedOrder) {
    const manifest = inputs.registry.manifestById.get(capabilityId);
    if (!manifest) {
      throw new CliError("unknown-capability", `capability '${capabilityId}' is not loaded`);
    }

    for (const rendered of renderManifestFiles(manifest, context)) {
      files.push({
        capabilityId,
        src: rendered.mapping.src,
        dst: rendered.mapping.dst,
        content: rendered.content.toString("utf8")
      });
    }
  }

  return {
    command: "generate",
    status: "generated",
    targetRoot: plan.targetRoot,
    configPath: plan.configPath,
    locale: plan.locale,
    deploymentOrder: selectedOrder,
    files
  };
}
