function crc = crc32(bytes)
%CRC32 CRC32/ISO-HDLC over original bytes, including the terminating LF.
persistent table
if isempty(table)
    table=zeros(1,256,'uint32');
    polynomial=uint32(hex2dec('EDB88320'));
    for k=0:255
        value=uint32(k);
        for bit=1:8
            if bitand(value,uint32(1)), value=bitxor(bitshift(value,-1),polynomial);
            else, value=bitshift(value,-1); end
        end
        table(k+1)=value;
    end
end
crc=uint32(hex2dec('FFFFFFFF'));
for byte=reshape(uint8(bytes),1,[])
    index=double(bitand(bitxor(crc,uint32(byte)),uint32(255)))+1;
    crc=bitxor(bitshift(crc,-8),table(index));
end
crc=bitxor(crc,uint32(hex2dec('FFFFFFFF')));
end
