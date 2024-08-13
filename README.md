# HyperPoint - Easy Checkpoints for GPU-Assigned Hyper-V Virtual Machines

Hyper-V does not allow checkpoints on a GPU-assigned virtual machines. HyperPoint removes assigned GPU adapters, creates checkpoint then reassigns GPU adapters. So, you can create checkpoints and continue to use your GPU(s) in your VMs.


## With HyperPoint, You Can
1) Create checkpoints for GPU-assigned VMs.
2) Add GPU adapter(s) by name, device ID, instance ID, device order or automatically.
3) Remove GPU adapter(s) by name, device ID, instance ID, device order or remove all of them.
4) List available GPU adapter(s) and view GPU details: name, device ID, instance ID, device order.
5) List assigned GPU adapter(s) and view GPU details: name, device ID, instance ID, device order.


## Cautions
1) **Do not try** to remove/add GPUs, create checkpoints while your target VM is running. This will definitely break snapshots, VM and your hearth. (Script already won't be executed while target VM is running, but keep this in mind.)
2) **Do not change** vmdisk contents from outside, like attaching VHDX file to host (e.g., if you want to update GPU drivers in the VM). It will also break checkpoints. It is recommended to change vmdisk contents inside the guest os via network-shared folders, etc.
3) Automatic checkpoints option won't work for GPU-assigned VM and will give error. Script also disables it.
4) HyperPoint has not been tested in all possible scenarios and environments. Make sure to backup your VM before using the script. **Use it at your own risk**.


## Parameters
| Param | Argument                      | Description                                                    |
|-------|-------------------------------|----------------------------------------------------------------|
| -VM   | "VM Name"                     | (**Mandatory**) Specify target vm to work on.                  |
| -DO   | "list-gpus"                   | List available PGPUs and assigned PGPUs.                       |
|       | "list-gpus-partitionable"     | List available PGPUs.                                          |
|       | "list-gpus-assigned"          | List assigned PGPUs.                                           |
|       | "add"                         | Add user-defined PGPU with '-GPU' param.                       |
|       | "add-auto"                    | Add PGPU automatically(1) or user-defined with '-GPU' param.   |
|       | "add-all"                     | Add all GPUs in the PGPU list.                                 |
|       | "remove"                      | Remove assigned user-defined PGPU with '-GPU' param.           |
|       | "remove-all"                  | Remove all assigned PGPUs.                                     |
|       | "reset"                       | It equals "remove-all" + "add-auto" params.                    |
| -GPU  | "gpu friendly device name"    | Define PGPU by friendly name(2)(3).                            |
|       | "deviceid:PCI\VEN..."         | Define PGPU by device ID(3).                                   |
|       | "instanceid:\\\\?\PCI#VEN..." | Define PGPU by instance ID(3).                                 |
|       | "order:[int]"                 | Define PGPU by partitionable GPU list order number(3).         |
|       | "adapterid:Microsoft:F65D..." | Define PGPU by adapter ID(4) (*For removal only*)              |
|       | "value1","value2","value3"... | Multiple PGPUs can be defined with comma-separated strings(5). |

> **(1):** If -GPU parameter is not defined; most suitable GPU will be selected automatically.

> **(2):** If there are multiple GPUs with the same name in the PGPU list, all of them will be grabbed.

> **(3):** These values can be obtained using the `-DO "list-gpus-partitionable"` parameter.

> **(4):** Adapter ID is necessary for only if you want to remove PGPU via adapter id.

> **(5):** Definitions can be mixed like `-GPU "Nvidia Geforce RTX 4060","order:3","deviceid:PCI\VEN..."`


## Usage Examples

### Checkpoint

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm"`
Removes assigned GPUs, creates checkpoint and reassigns GPUs. 
*Notice: The GPU's Instance ID is required when reassigning it to a VM. If you have assigned a GPU using the `Add-VMGpuPartitionAdapter` command without specifying the instance ID, it won't have an instance ID and cannot be reassigned automatically. Simply use HyperPoint to add GPU adapters. HyperPoint guarantees instance ID for every assigned GPU.*

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -GPU "Nvidia GeForce RTX 4060"`
Removes assigned GPUs, **creates checkpoint**, assigns all GPUs named 'NVIDIA GeForce RTX 4060' instead of the previous assigned GPUs.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -GPU "deviceid:PCI\VEN_10DE&DEV_2206&SUBSYS_38971462&REV_A1\4&17F0F7D2&0&0008"`
Removes assigned GPUs, **creates checkpoint**, assigns GPU with the given device ID instead of the previous assigned GPUs.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -GPU "instanceid:\\?\PCI#VEN_10DE&DEV_2206&SUBSYS_38971462&REV_A1#4&17f0f7d2&0&0008#{064092b3-625e-43bf-9eb5-dc845897dd59}\GPUPARAV"`
Removes assigned GPUs, **creates checkpoint**, assigns user-defined GPU with the given instance ID instead of the previous assigned GPUs.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -GPU "radeon rx 6800 xt","order:5"`
Removes assigned GPUs, **creates checkpoint**, assigns all GPUs named 'Radeon RX 6800 XT' and the fifth GPU in the PGPU list the instead of previous assigned GPUs.

### Listing GPUs

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "list-gpus"`
Shows the partitionable GPUs and assigned GPUs lists.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "list-gpus-partitionable"`
Shows the partitionable GPUs list.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "list-gpus-assigned"`
Shows the assigned GPUs list.

### Adding GPUs

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "add" -GPU "radeon RX 6800 XT"`
Assigns all GPUs named 'Radeon RX 6800 XT' to VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "add-auto"`
Automatically assigns the first suitable GPU to the VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "add-all"`
Assigns all GPUs in the PGPUs list.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "add-auto" -GPU "nvidia geforce rtx 4060"`
If the device(s) exists, assigns all GPUs named 'NVIDIA GeForce RTX 4060'; if not, automatically assigns the first suitable GPU to the VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "add" -GPU "nvidia geforce rtx 4060","radeon rx 6800 xt"`
Assigns 'NVIDIA GeForce RTX 4060' and 'Radeon RX 6800 XT' to vm.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "add" -GPU "Radeon RX 6800 XT","order:4","deviceid:PCI\VEN_10DE&DEV_2206&SUBSYS_38971462&REV_A1\4&17F0F7D2&0&0008"`
Assigns 'Radeon RX 6800 XT', the fourth GPU in the PGPU list, and the GPU with the given device ID.

### Removing GPUs

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "remove" -GPU "Radeon RX 6800 XT"`
Removes all GPUs named "Radeon RX 6800 XT" from the VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "remove" -GPU "NVIDIA GeForce RTX 4060","order:2"`
Removes all GPUs named "NVIDIA GeForce RTX 4060" and the second GPU in the PGPU list from VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "remove-all"`
Removes all GPUs from VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "reset"`
Performs "remove-all" and "add-auto" processes in order.
