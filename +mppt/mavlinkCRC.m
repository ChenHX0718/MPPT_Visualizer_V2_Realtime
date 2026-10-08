function crc = mavlinkCRC(bytes)
%MAVLINKCRC MAVLink X.25 accumulation, including caller-provided CRC_EXTRA.
crc=uint16(65535);
for byte=reshape(uint8(bytes),1,[])
    tmp=bitxor(uint16(byte),bitand(crc,uint16(255)));
    tmp=bitand(bitxor(tmp,bitshift(tmp,4)),uint16(255));
    crc=bitxor(bitxor(bitxor(bitshift(crc,-8),bitshift(tmp,8)), ...
        bitshift(tmp,3)),bitshift(tmp,-4));
end
end
