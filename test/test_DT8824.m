[cDirThis, cName, cExt] = fileparts(mfilename('fullpath'));
cDirSrc = fullfile(cDirThis,  '..', 'src');
addpath(genpath(cDirSrc));


cDirMpm = fullfile(cDirThis, '..', 'mpm-packages');
addpath(genpath(cDirMpm));

%% Initialize
cHost = '192.168.50.1';
u16Port = uint16(5025);

comm = dt.DT8824(...
    'cTcpipHost', cHost, ...
    'u16TcpipPort', u16Port ...
);

%% Initialize
comm.abortScan()
comm.clearBytesAvailable();
[cIdn, lSuccess] = comm.getIdentity()
comm.enablePasswordProtectedCommands()
[l, lSuccess] = comm.getPasswordProtectedCommandsEnabled()

%%
comm.disableAllChannels()
comm.getEnabledChannels()
% comm.enableAllChannels()
comm.enableChannels([1, 2, 3]);
comm.getEnabledChannels()

%%
comm.getSamplingFrequency()
comm.setSamplingFrequency(2000);
comm.getSamplingFrequency()
comm.setSamplingFrequencyToMax()
comm.getSamplingFrequency()

%%
comm.getStatus()
comm.getWrapModeOfBuffer()
comm.setWrapModeOfBufferToWrap()
comm.getWrapModeOfBuffer()
comm.setWrapModeOfBufferToDefault()
comm.getWrapModeOfBuffer()

%%
comm.getStatus()
comm.armSystem()
comm.initiateScan()

%%
comm.getScanData()

%%
comm.getSizeOfScanBuffer()
[dStart, dEnd] = comm.getIndicesOfScanBuffer()

%%


delete(comm);