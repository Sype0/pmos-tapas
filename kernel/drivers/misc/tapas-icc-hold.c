// SPDX-License-Identifier: GPL-2.0-only
/*
 * Hold a memory bandwidth vote for a scanout nobody in the kernel owns.
 *
 * On tapas the display runs on what the bootloader set up (simpledrm on
 * its splash buffer); the MDSS/DPU driver is off, so nothing votes for the
 * MDP's path to DDR. Once the interconnect framework's sync_state drops the
 * boot-time votes, DDR may clock down below what the 120 Hz, 1080x2400
 * scanout fetches, and the DPU underruns: the picture breaks up now and
 * then. This driver puts that vote back:
 *
 *	display-bw-hold {
 *		compatible = "tapas,icc-hold";
 *		interconnects = <&mmrt_virt MASTER_MDP_PORT0 RPM_ALWAYS_TAG
 *				 &bimc SLAVE_EBI_CH0 RPM_ALWAYS_TAG>;
 *		tapas,bandwidth-kBps = <avg peak>;
 *	};
 */
#include <linux/interconnect.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>

static int icc_hold_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct icc_path *path;
	u32 bw[2];
	int ret;

	ret = of_property_read_u32_array(dev->of_node, "tapas,bandwidth-kBps",
					 bw, ARRAY_SIZE(bw));
	if (ret)
		return dev_err_probe(dev, ret, "no tapas,bandwidth-kBps\n");

	path = devm_of_icc_get(dev, NULL);
	if (IS_ERR_OR_NULL(path))
		return dev_err_probe(dev, path ? PTR_ERR(path) : -ENODEV,
				     "no interconnect path\n");

	ret = icc_set_bw(path, bw[0], bw[1]);
	if (ret)
		return dev_err_probe(dev, ret, "icc_set_bw failed\n");

	dev_info(dev, "holding %u kBps average, %u kBps peak\n", bw[0], bw[1]);
	return 0;
}

static const struct of_device_id icc_hold_of_match[] = {
	{ .compatible = "tapas,icc-hold" },
	{ }
};
MODULE_DEVICE_TABLE(of, icc_hold_of_match);

static struct platform_driver icc_hold_driver = {
	.probe = icc_hold_probe,
	.driver = {
		.name = "tapas-icc-hold",
		.of_match_table = icc_hold_of_match,
	},
};
module_platform_driver(icc_hold_driver);

MODULE_DESCRIPTION("Interconnect bandwidth vote for the bootloader's scanout");
MODULE_LICENSE("GPL");
