from pathlib import Path
import re, subprocess, shlex
root=Path(__file__).resolve().parents[1]
log=(root/'.tools/device-link-verbose.log').read_text(encoding='utf-8-sig')
responses=re.findall(r'^Response file: @[^:]+: \{(.*)\}$',log,re.M)
assert len(responses)==2,len(responses)
decoded=[x.replace('<LF>','\n').replace('\\\\','\\') for x in responses]
script=root/'.tools/device-input.ld';script.write_text(decoded[1])
args=decoded[0].splitlines();args[0]=str(script)
tc=root/'.tools/toolchains/gnat_arm_elf_14.2.1_2c52e01a'
gcc=tc/'bin/arm-eabi-gcc.exe'
boot=next(x for x in args if x.endswith('boot2__w25qxx.S'))
obj=root/'.tools/boot2.o'
subprocess.run([str(gcc),'-c','-mcpu=cortex-m0plus','-mthumb','-mfloat-abi=soft',boot,'-o',str(obj)],cwd=root/'device/bin',check=True)
args[args.index(boot)]=str(obj)
r=subprocess.run([str(gcc),'-###']+args,cwd=root/'device/bin',text=True,capture_output=True)
(root/'.tools/gcc-link-plan.log').write_text(r.stderr)
line=next(x.strip() for x in r.stderr.splitlines() if 'collect2' in x and x.lstrip().startswith('"'))
cmd=shlex.split(line)
cmd[0]=str(tc/'bin/arm-eabi-ld.exe')
clean=[];i=0
while i<len(cmd):
    if cmd[i]=='-plugin': i+=2;continue
    if cmd[i].startswith('-plugin-opt='): i+=1;continue
    clean.append(cmd[i]);i+=1
(root/'.tools/ld-args.txt').write_text('\n'.join(clean))
r=subprocess.run(clean,cwd=root/'device/bin',text=True,capture_output=True)
print(r.stdout);print(r.stderr)
raise SystemExit(r.returncode)
