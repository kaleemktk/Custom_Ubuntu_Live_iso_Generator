# Custom_Ubuntu_Live_iso_Generator
Modify Ubuntu Live Casper Image
Tested with Ubuntu Versions 22.xx.xx
Script entry point is ./main.sh <br>
<h3>Arguments:</h3>
<h4>Required: </h4>
&emsp;&emsp;&emsp;-i_iso          &emsp;&emsp;- Input ISO Original.<br>
<h4>Optional:</h4>
&emsp;&emsp;&emsp;-h|--help       &emsp;&emsp;- Print this help menu.<br>
&emsp;&emsp;&emsp;-o_iso          &emsp;&emsp;- Output ISO file. Default is CWD/custom.iso.<br>
&emsp;&emsp;&emsp;-work_dir       &emsp;&emsp;- Directory to dump all the files temporarily. Default is CWD.<br>
&emsp;&emsp;&emsp;-apt            &emsp;&emsp;- File listing all apt pkgs to install on the custom ISO. Default installs none.<br>
&emsp;&emsp;&emsp;-d|--debug			&emsp;&emsp;- Enable command printing for debugging.<br>
<br>
