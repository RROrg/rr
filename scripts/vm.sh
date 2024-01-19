
filename=$(basename "${1}")

OVFNAME=${filename%.*}
BLDISKNAME="${OVFNAME}-disk1.vmdk"
SDDISKNAME="${OVFNAME}-disk2.vmdk"

# Convert raw image to VMDK
qemu-img convert -O vmdk -o 'adapter_type=lsilogic,subformat=streamOptimized,compat6' "${1}" "${BLDISKNAME}"
#qemu-img create -f vmdk "${SDDISKNAME}" "32G"

BLSIZE=$(du -b "${BLDISKNAME}" | cut -f 1)
SDSIZE=$(du -b "${SDDISKNAME}" | cut -f 1)
BLVIRTUALSIZE=$(qemu-img info "${BLDISKNAME}" --output json | jq -r '."virtual-size"')
SDVIRTUALSIZE=$(qemu-img info "${SDDISKNAME}" --output json | jq -r '."virtual-size"')

# Create VM configuration
cat << _EOF_ > "${OVFNAME}.ovf"
<?xml version="1.0" encoding="UTF-8"?>
<Envelope vmw:buildId="build-22220919" xmlns="http://schemas.dmtf.org/ovf/envelope/1" xmlns:cim="http://schemas.dmtf.org/wbem/wscim/1/common" xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1" xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData" xmlns:vmw="http://www.vmware.com/schema/ovf" xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <References>
    <File ovf:href="${BLDISKNAME}" ovf:id="file1" ovf:size="${BLSIZE}"/>
    <File ovf:href="${SDDISKNAME}" ovf:id="file2" ovf:size="${SDSIZE}"/>
  </References>
  <DiskSection>
    <Info>Virtual disk information</Info>
    <Disk ovf:capacity="${BLVIRTUALSIZE}" ovf:capacityAllocationUnits="byte" ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized" ovf:populatedSize="${BLSIZE}"/>
    <Disk ovf:capacity="${SDVIRTUALSIZE}" ovf:capacityAllocationUnits="byte" ovf:diskId="vmdisk2" ovf:fileRef="file2" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized" ovf:populatedSize="${SDSIZE}"/>
  </DiskSection>
  <NetworkSection>
    <Info>The list of logical networks</Info>
    <Network ovf:name="bridged">
      <Description>The bridged network</Description>
    </Network>
  </NetworkSection>
  <VirtualSystem ovf:id="vm">
    <Info>A virtual machine</Info>
    <Name>${OVFNAME}</Name>
    <OperatingSystemSection ovf:id="94" vmw:osType="ubuntu64Guest">
      <Info>The kind of installed guest operating system</Info>
    </OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware requirements</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemIdentifier>${OVFNAME}</vssd:VirtualSystemIdentifier>
        <vssd:VirtualSystemType>vmx-21</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>
        <rasd:Description>Number of Virtual CPUs</rasd:Description>
        <rasd:ElementName>2 virtual CPU(s)</rasd:ElementName>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>2</rasd:VirtualQuantity>
        <vmw:CoresPerSocket ovf:required="false">2</vmw:CoresPerSocket>
      </Item>
      <Item>
        <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:ElementName>4096MB of memory</rasd:ElementName>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>4096</rasd:VirtualQuantity>
        <vmw:CoresPerSocket ovf:required="false">1</vmw:CoresPerSocket>
      </Item>
      <Item>
        <rasd:Address>0</rasd:Address>
        <rasd:Description>SATA Controller</rasd:Description>
        <rasd:ElementName>sataController0</rasd:ElementName>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceSubType>vmware.sata.ahci</rasd:ResourceSubType>
        <rasd:ResourceType>20</rasd:ResourceType>
        <vmw:CoresPerSocket ovf:required="false">1</vmw:CoresPerSocket>
      </Item>
      <Item ovf:required="false">
        <rasd:Address>0</rasd:Address>
        <rasd:Description>USB Controller (XHCI)</rasd:Description>
        <rasd:ElementName>usb3</rasd:ElementName>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:ResourceSubType>vmware.usb.xhci</rasd:ResourceSubType>
        <rasd:ResourceType>23</rasd:ResourceType>
        <vmw:CoresPerSocket ovf:required="false">1</vmw:CoresPerSocket>
      </Item>
      <Item ovf:required="false">
        <rasd:Address>0</rasd:Address>
        <rasd:Description>USB Controller (EHCI)</rasd:Description>
        <rasd:ElementName>usb</rasd:ElementName>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceSubType>vmware.usb.ehci</rasd:ResourceSubType>
        <rasd:ResourceType>23</rasd:ResourceType>
        <vmw:Config ovf:required="false" vmw:key="ehciEnabled" vmw:value="true"/>
        <vmw:CoresPerSocket ovf:required="false">1</vmw:CoresPerSocket>
      </Item>
      <Item ovf:required="false">
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:ElementName>serial0</rasd:ElementName>
        <rasd:InstanceID>6</rasd:InstanceID>
        <rasd:ResourceType>21</rasd:ResourceType>
        <vmw:Config ovf:required="false" vmw:key="yieldOnPoll" vmw:value="false"/>
        <vmw:Config ovf:required="false" vmw:key="connectable.allowGuestControl" vmw:value="false"/>
        <vmw:CoresPerSocket ovf:required="false">1</vmw:CoresPerSocket>
      </Item>
      <Item>
        <rasd:AddressOnParent>1</rasd:AddressOnParent>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Connection>bridged</rasd:Connection>
        <rasd:Description>VmxNet3 ethernet adapter on &quot;bridged&quot;</rasd:Description>
        <rasd:ElementName>ethernet0</rasd:ElementName>
        <rasd:InstanceID>7</rasd:InstanceID>
        <rasd:ResourceSubType>VmxNet3</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
        <vmw:Config ovf:required="false" vmw:key="connectable.allowGuestControl" vmw:value="false"/>
        <vmw:CoresPerSocket ovf:required="false">1</vmw:CoresPerSocket>
      </Item>
      <Item ovf:required="false">
        <rasd:AutomaticAllocation>false</rasd:AutomaticAllocation>
        <rasd:ElementName>sound</rasd:ElementName>
        <rasd:InstanceID>8</rasd:InstanceID>
        <rasd:ResourceSubType>vmware.soundcard.ensoniq1371</rasd:ResourceSubType>
        <rasd:ResourceType>1</rasd:ResourceType>
        <vmw:CoresPerSocket ovf:required="false">1</vmw:CoresPerSocket>
      </Item>
      <Item ovf:required="false">
        <rasd:AutomaticAllocation>false</rasd:AutomaticAllocation>
        <rasd:ElementName>video</rasd:ElementName>
        <rasd:InstanceID>9</rasd:InstanceID>
        <rasd:ResourceType>24</rasd:ResourceType>
        <vmw:Config ovf:required="false" vmw:key="enable3DSupport" vmw:value="true"/>
        <vmw:CoresPerSocket ovf:required="false">1</vmw:CoresPerSocket>
      </Item>
      <Item ovf:required="false">
        <rasd:AutomaticAllocation>false</rasd:AutomaticAllocation>
        <rasd:ElementName>vmci</rasd:ElementName>
        <rasd:InstanceID>10</rasd:InstanceID>
        <rasd:ResourceSubType>vmware.vmci</rasd:ResourceSubType>
        <rasd:ResourceType>1</rasd:ResourceType>
        <vmw:CoresPerSocket ovf:required="false">1</vmw:CoresPerSocket>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:ElementName>disk0</rasd:ElementName>
        <rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>
        <rasd:InstanceID>11</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
        <vmw:CoresPerSocket ovf:required="false">1</vmw:CoresPerSocket>
      </Item>
      <Item>
        <rasd:AddressOnParent>1</rasd:AddressOnParent>
        <rasd:ElementName>disk1</rasd:ElementName>
        <rasd:HostResource>ovf:/disk/vmdisk2</rasd:HostResource>
        <rasd:InstanceID>12</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
        <vmw:CoresPerSocket ovf:required="false">1</vmw:CoresPerSocket>
      </Item>
      <vmw:Config ovf:required="false" vmw:key="cpuHotAddEnabled" vmw:value="true"/>
      <vmw:Config ovf:required="false" vmw:key="memoryHotAddEnabled" vmw:value="true"/>
      <vmw:Config ovf:required="false" vmw:key="firmware" vmw:value="efi"/>
      <vmw:Config ovf:required="false" vmw:key="simultaneousThreads" vmw:value="1"/>
      <vmw:Config ovf:required="false" vmw:key="virtualNuma.coresPerNumaNode" vmw:value="0"/>
      <vmw:Config ovf:required="false" vmw:key="tools.syncTimeWithHost" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="powerOpInfo.powerOffType" vmw:value="soft"/>
      <vmw:Config ovf:required="false" vmw:key="powerOpInfo.resetType" vmw:value="soft"/>
      <vmw:Config ovf:required="false" vmw:key="powerOpInfo.suspendType" vmw:value="soft"/>
      <vmw:ExtraConfig ovf:required="false" vmw:key="cpuid.coresPerSocket" vmw:value="2"/>
      
      <vmw:ExtraConfig ovf:required="false" vmw:key="hpet0.present" vmw:value="TRUE"/>
      
      <vmw:ExtraConfig ovf:required="false" vmw:key="nvram" vmw:value="${OVFNAME}.nvram"/>
      <vmw:ExtraConfig ovf:required="false" vmw:key="pciBridge0.present" vmw:value="TRUE"/>
      <vmw:ExtraConfig ovf:required="false" vmw:key="pciBridge4.functions" vmw:value="8"/>
      <vmw:ExtraConfig ovf:required="false" vmw:key="pciBridge4.present" vmw:value="TRUE"/>
      <vmw:ExtraConfig ovf:required="false" vmw:key="pciBridge4.virtualDev" vmw:value="pcieRootPort"/>
      <vmw:ExtraConfig ovf:required="false" vmw:key="pciBridge5.functions" vmw:value="8"/>
      <vmw:ExtraConfig ovf:required="false" vmw:key="pciBridge5.present" vmw:value="TRUE"/>
      <vmw:ExtraConfig ovf:required="false" vmw:key="pciBridge5.virtualDev" vmw:value="pcieRootPort"/>
      <vmw:ExtraConfig ovf:required="false" vmw:key="pciBridge6.functions" vmw:value="8"/>
      <vmw:ExtraConfig ovf:required="false" vmw:key="pciBridge6.present" vmw:value="TRUE"/>
      <vmw:ExtraConfig ovf:required="false" vmw:key="pciBridge6.virtualDev" vmw:value="pcieRootPort"/>
      <vmw:ExtraConfig ovf:required="false" vmw:key="pciBridge7.functions" vmw:value="8"/>
      <vmw:ExtraConfig ovf:required="false" vmw:key="pciBridge7.present" vmw:value="TRUE"/>
      <vmw:ExtraConfig ovf:required="false" vmw:key="pciBridge7.virtualDev" vmw:value="pcieRootPort"/>
      
      <vmw:ExtraConfig ovf:required="false" vmw:key="usb.vbluetooth.startConnected" vmw:value="TRUE"/>
      
      <vmw:ExtraConfig ovf:required="false" vmw:key="virtualHW.productCompatibility" vmw:value="hosted"/>
    </VirtualHardwareSection>
    <AnnotationSection ovf:required="false">
      <Info>A human-readable annotation</Info>
      <Annotation>Redpill Recovery</Annotation>
    </AnnotationSection>
  </VirtualSystem>
</Envelope>
_EOF_

# Create manifest file for automatic integrity check
cat << _EOF_ > "${OVFNAME}.mf"
SHA256(${OVFNAME}.ovf)= $(sha256sum "${OVFNAME}.ovf" | mawk '{print $1}')
SHA256(${BLDISKNAME})= $(sha256sum "${BLDISKNAME}" | mawk '{print $1}')
SHA256(${SDDISKNAME})= $(sha256sum "${SDDISKNAME}" | mawk '{print $1}')
_EOF_

# Pack everything as OVA appliance for ESXi import
rm -f "${OVFNAME}.ova"
tar -cf "${OVFNAME}.ova" ${OVFNAME}.ovf ${BLDISKNAME} ${SDDISKNAME} ${OVFNAME}.mf
rm -f ${OVFNAME}.ovf ${BLDISKNAME} ${SDDISKNAME} ${OVFNAME}.mf
#gzip "${OVFNAME}.ova"

