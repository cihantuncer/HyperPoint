# HyperPoint - Easy Checkpoints for GPU-Assigned Hyper-V Virtual Machines

Hyper-V does not allow checkpoints on GPU-assigned virtual machines. HyperPoint removes assigned GPU adapters, creates checkpoint then reassigns GPU adapters. So, you can create checkpoints and continue to use your GPU(s) in your VMs.

<br><br>

## With HyperPoint, You Can
1) Create checkpoints for GPU-assigned VMs.
2) Gather GPU drivers from host machine and auto-install them in the VM. 
3) Add GPU adapter(s) by name, device ID, instance ID, device order or automatically.
4) Remove GPU adapter(s) by name, device ID, instance ID, device order or remove all of them.
5) List available GPU adapter(s) and view GPU details: name, device ID, instance ID, device order.
6) List assigned GPU adapter(s) and view GPU details: name, device ID, instance ID, device order.

<br><br>
**For detailed information see [Usage Examples](https://github.com/cihantuncer/HyperPoint/wiki/Usage-Examples) on Wiki**
<br><br>

## Cautions
1) **Do not attempt** to remove/add GPUs or create checkpoints while your target VM is running. This will definitely break snapshots, the VM, and possibly your heart. (The checkpoint, add, remove processes already won't execute while the target VM is running, but keep this in mind.)
2) **Do not modify** the VM disk contents from outside, such as by attaching the VHDX file to the host (e.g., if you want to update GPU drivers in the VM). This will also break checkpoints (You will need to remove the VM, create a new one, and attach the old VM disk). It is recommended to modify VM disk contents from within the guest OS. You can easily install/update drivers via HyperPoint (See Usage Examples).
3) The automatic checkpoint option won't work for GPU-assigned VMs and will result in an error. The script also disables this option.
4) HyperPoint has not been tested in all possible scenarios and environments. Make sure to **backup your VM** before using the script. **Use it at your own risk**.

<br>

Note: Do not forget set the execution policy to "RemoteSigned" before executing the script via `Set-ExecutionPolicy RemoteSigned`

 <br><br>
   
## Parameters

| Param   | Argument                       | Description                                                     |
|---------|--------------------------------|-----------------------------------------------------------------|
| -VM     | "VM Name"                      | Specify target VM to work on.                                   |
| -DO     | "list-gpus"                    | List available PGPUs and assigned PGPUs.                        |
|         | "list-gpus-partitionable"      | List available PGPUs.                                           |
|         | "list-gpus-assigned"           | List assigned PGPUs.                                            |
|         | "add"                          | Add user-defined PGPU with '-GPU' param.                        |
|         | "add-auto"                     | Add PGPU automatically(1) or user-defined with '-GPU' param.    |
|         | "add-all"                      | Add all GPUs in the PGPU list.                                  |
|         | "remove"                       | Remove assigned user-defined PGPU with '-GPU' param.            |
|         | "remove-all"                   | Remove all assigned PGPUs.                                      |
|         | "reset"                        | Equivalent to "remove-all" + "add-auto" params.                 |
|         | "get-drivers"                  | Gather driver files for assigned or defined with param GPUs(6). |
| -ZIP    |                                | Compress driver files into a zip package(6).                    |
| -DEST   | "Path\To\DriverPackagesFolder" | The target directory for gathered driver files(6).              |
| -GPU    | "gpu friendly device name"     | Specify the  PGPU by friendly name(2)(3).                       |
|         | "deviceid:PCI\VEN..."          | Specify PGPU by device ID(3).                                   |
|         | "instanceid:\\\\?\PCI#VEN..."  | Specify PGPU by instance ID(3).                                 |
|         | "order:[int]"                  | Specify PGPU by partitionable GPU list order number(3).         |
|         | "adapterid:Microsoft:F65D..."  | Specify PGPU by adapter ID(4) (*For removal only*)              |
|         | "value1","value2","value3"...  | Multiple PGPUs can be defined with comma-separated values(5).   |

### installdrivers.ps1 Parameters

| Param   | Argument                       | Description                                                     |
|---------|--------------------------------|-----------------------------------------------------------------|
| -SRC    | "Path\To\DriverPackagesFolder" | Specify directory that contains driver packages(7).             |
| -DRV    | "Package Name"                 | Specify driver package(s) to install(8).                        |
|         | "Package1","Package2",...      | Multiple packages can be defined with comma-separated values(8).|
| -DRVSRC | "Path\To\DriverPackage(.zip)"  | Direct path to driver package folder or zip(9).                 |
| -FORCE  |                                | Force install the driver(10).                                   |

<br>

> **(1):** If -GPU parameter is not defined; first suitable GPU will be selected automatically.

> **(2):** If there are multiple GPUs with the same name in the PGPU list, all of them will be grabbed.

> **(3):** These values can be obtained using the `-DO "list-gpus-partitionable"` parameter.

> **(4):** Adapter ID is necessary for only if you want to remove GPU via adapter id.

> **(5):** Definitions can be mixed e.g., `-GPU "Nvidia Geforce RTX 4060","order:3","deviceid:PCI\VEN..."`

> **(6):** You can gather GPU driver files from the host using the -DO "get-drivers" parameter to the default (\path\to\script\hostdrivers) or a user-defined location with the -DEST "\path\to\destination" parameter. This directory will contain GPU driver files in a package folder (e.g., \path\to\script\hostdrivers\NVIDIA_20240814) or a zipped package (e.g., \path\to\script\hostdrivers\NVIDIA_20240814.zip) created using the -ZIP parameter.

> **(7):** The default source is the "\path\to\script\hostdrivers" folder. It can be changed using the -SRC "path\to\DriverPackagesFolder" parameter. This directory must contain driver package folders (e.g., \NVIDIA_20240814) or zipped packages (e.g., NVIDIA_20240814.zip).

> **(8):** By default, the script installs all driver packages available in the packages folder. You can choose which driver package(s) to install using the -DRV "Package Name" parameter. Multiple folder and zip packages can be specified, e.g., "NVIDIA_20240814","AMD_20240312.zip"

> **(9):** The -DRVSRC "path\to\driverPackage(.zip)" parameter directly installs driver files to the VM.

> **(10):** The -FORCE parameter tries to unlock files locked by other processes during installation.

<br><br>

