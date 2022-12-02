classdef DT8824 < Comm & dt.DT8824Abstract
    %UNTITLED Summary of this class goes here
    %   Detailed explanation goes here
    
    properties (Access = private)
        
        % {logical 1x1} true whend doing a long read. Causes other read
        % commands to not communicate with hardware and return bogus value

        % Cache for getData
        ticGetVariables
        tocMin = 0.2;
        dScanData % {double 1 x m} see getScanData()

        % {double 1x1} storage of the number of times getScanData()
        % has thrown an error.  
        dNumOfSequentialGetScanDataErrors = 0

        % {double 1x1} storage of the last successfully read index start and
        % index end of the scan buffer
        dIndexStart = 1;
        dIndexEnd = 1;
    end
    
    methods
        
        function this = DT8824(varargin)
            
            % Call superclass Comm constructor
            this = this@Comm(varargin{:});
            
            this.cConnection = this.cCONNECTION_TCPCLIENT;
            
            % ascii config
            this.u8TerminatorWrite = uint8([10]); % new line
            this.u8TerminatorRead = uint8([10]);
        
            this.init(); % Comm.init()
            
        end
        
        function delete(this)
            this.comm = [];
        end
        
        
        
        % {u8Channel} zero-indexed channel of the instrument
        function [d, lError] = getScanDataOfChannel(this, u8Channel)
            [dAll, lError] = this.getScanData();
            d = dAll(u8Channel + 1);

        end


        % Returns {double n x 48} scan records from the circular
        % buffer where n is the lower of the number chronologically newer
        % than the provided index or the maximum number of records supported
        % by the size of the network packet, which is 20 records when each
        % record contains 48 channel.  It also returns the end index
        % @param {double 1x1} dIndex - [0 - large number]

        function [result, dIndexEnd] = getScanDataAheadOfIndex(this, dIndex)

            this.lIsBusy = true;
            % Ask the hardware for the most recent index of the circular buffer
            % that was filled and do a FETCH to get data from it
            [dIndexStart, dIndexEnd] = this.getIndiciesOfScanBuffer();

            % Error checking
            if dIndex < dIndexStart
                dIndex = dIndexStart;
            end

            if dIndexEnd == 0
                result = zeros(1, 48);
                return;
            end

            if dIndex > dIndexEnd
                dIndex = dIndexEnd - 1;
            end

            dNum = dIndexEnd - dIndex;
            if dNum > 220 % max supported by network packet 
                dNum = 220; 
            end

            result = this.getScanDataSet(dIndex, dNum);
            dIndexEnd = dIndex + dNum;
            this.lIsBusy = false;

        end

        % Returns {double n x 49} scan records from the circular
        % buffer between indicies dIndex and dIndex + dNumRecords
        % The amount of data that is return is limited by the packet size of the network. 
        % The absolute limitation on TCP packet size is 64K (65535 bytes),
        % but in practicality this is far larger than the size of any
        % packet you will see, because the lower layers (e.g. ethernet)
        % have lower packet sizes which is about 20 records when the records
        % contain 48 channels each
        % @param {double 1x1} dIndex - [0 - large number]
        % @param {double 1x1} dNumRecords - number of records to retrieve

        function [result] = getScanDataSet(this, dIndex, dNumRecords)

            % NOTE
            this.lIsBusy = true;

            % Error checking based on populated indicies of the buffer

            [dIndexStart, dIndexEnd] = this.getIndiciesOfScanBuffer();
            if dIndex < dIndexStart
                dIndex = dIndexStart;
            end

            if dIndexEnd - dIndexStart < dNumRecords
                dNumRecords = dIndexEnd - dIndexStart;
            end

            if dNumRecords == 0
                result = zeros(1, 49);
                return
            end

            
            cCmd = sprintf(':AD:FETCH? %d, %d', dIndex, dNumRecords); 
            [c, lSuccess] = this.queryAscii(cCmd);
            
            idx = 1;
            % Skip starting character of <BLOCK> #
            idx = idx + 1;
            % Read next byte (char) which specifies how many bytes are
            % in the next field 
            dNumBytesNext = str2double(c(idx));
            % advance idx
            idx = idx + 1;
            % The next chunk is an ASCII string representation of the
            % number of bytes in the data block, including the data header
            dNumBytes = str2double(c(idx:idx+dNumBytesNext - 1))
            % Advence idx
            idx = idx + dNumBytesNext;
            
            % Extract the header (20 bytes) and the data
            u8Header = uint8(c(idx:idx+19));
            u8Data = uint8(c(idx+20:end));
            
            
            u8Index = u8Header(1:4);
            u8Num = u8Header(5:8);
            u8Samples = u8Header(9:12);
            u8Timestamp = u8Header(13:16);
            u8Last = u8Header(17:end);
            % can't figure out what last four bytes of the header are and
            % support also didn't know and was confused becasue there is
            % conflicting information in the docs
            
            dIndex = this.int8StreamToDec(u8Index)
            dNumBytesData = this.int8StreamToDec(u8Num) % num bytes in this block
            dSamples = this.int8StreamToDec(u8Samples) % Accumulated number of samples in buffer for each channelu
            dTimestamp =  this.int8StreamToDec(u8Timestamp)
            dLast = this.int8StreamToDec(u8Last)


            result = zeros(dNumRecords, 4);
            
            % Channels 0 - 47 result (float)
            dNumChannels = floor(dNumBytesData/4);
            result = zeros(dNumRecords, dNumChannels);
            index = 1; 
            dBytesPerSample = 4;
            for m = 1 : dNumRecords
                for n = 1 : dNumChannels 
                    u8DataOfChan = u8Data(index: index + dBytesPerSample - 1);
                    binDataOfChan = this.int8ToBin(u8DataOfChan);
                    index = index + dBytesPerSample;
                    result(m, n) = ieee.IeeeUtils.bin32ToNumMulti(binDataOfChan);
                end
            end
            
            this.lIsBusy = false;

        end
    
        % Returns {u8 1x20} header and {u8 1x?} data from <Block> Data Type
        % returned by :AD:FETCH queries with response formatted as ASCII
        
        function [u8Header, u8Data] = getHeaderAndDataFromBlock(this, c)
            
            idx = 1;
            % Skip starting character of <BLOCK> #
            idx = idx + 1;
            % Read next byte (char) which specifies how many bytes are
            % in the next field 
            dNumBytesNext = str2double(c(idx));
            % advance idx
            idx = idx + 1;
            % The next chunk is an ASCII string representation of the
            % number of bytes in the data block, including the data header
            dNumBytes = str2double(c(idx:idx+dNumBytesNext - 1));
            % Advence idx
            idx = idx + dNumBytesNext;
            
            % Extract the header (20 bytes) and the data
            u8Header = uint8(c(idx:idx+19));
            u8Data = uint8(c(idx+20:end));
            
        end
        
        % Returns {struct 1x1} with 
        
        
        function st = getHeaderInfo(this, u8Header)
            
            u8Index = u8Header(1:4);
            u8Num = u8Header(5:8);
            u8Samples = u8Header(9:12);
            u8Timestamp = u8Header(13:16);
            u8Last = u8Header(17:end);
            % can't figure out what last four bytes of the header are and
            % support also didn't know and was confused becasue there is
            % conflicting information in the docs
            
            dIndex = this.int8StreamToDec(u8Index);
            dNumBytesData = this.int8StreamToDec(u8Num); % num bytes in this block
            dSamples = this.int8StreamToDec(u8Samples); % Accumulated number of samples in buffer for each channelu
            dTimestamp =  this.int8StreamToDec(u8Timestamp);
            dLast = this.int8StreamToDec(u8Last);
            
            st = struct();
            st.dIndex = dIndex;
            st.dNumBytesData = dNumBytesData;
            st.dSamples = dSamples;
            st.dTimestamp = dTimestamp;
            st.dLast = dLast;
            
        end
        
        
        % See <Block> Data Type in the DT8824 programmers manual
        % Returns {double 1x4} fresh value of every channel from the circular
        % buffer on the instrument.     
        % setScanList
        % setScanRate
        % setSizeOfScanBuffer
        % setScanTriggeSourceToDefault
        % setSensorType
        % initiateScan
        % abortScan
        function [result, lError] = getScanData(this)

            % reset {logical} error
            lError = false;

            % Check if should return cached value
            if ~isempty(this.ticGetVariables)
                if (toc(this.ticGetVariables) < this.tocMin)
                    % Use cache
                    result = this.dScanData;
                    % fprintf('datatranslation.MeasurPoint.getScanData() using cache\n');
                    return;
                end
            end

            this.lIsBusy = true;

            % Ask the hardware for the most recent index of the circular buffer
            % that was filled and do a FETCH to get data from it
            [dIndexStart, dIndexEnd] = this.getIndicesOfScanBuffer()
            cCmd = sprintf(':AD:FETCH? %d, 1', dIndexEnd);
            [c, lSuccess] = this.queryAscii(cCmd);
            
            if lSuccess == false
                cMsg = [...
                        '+dt/DT8824.getScanData()', ...
                        'read error. ', ...
                        'Returning last good data and lError = true.\n'
                    ];
                    fprintf(cMsg);
                lError = true;
                result = this.dScanData;
                return;
            end
            
            [u8Header, u8Data] = this.getHeaderAndDataFromBlock(c);
            stHeader = this.getHeaderInfo(u8Header)
            
                        
            % Channels 0 - 47 result (float)
            dNumBytesPerSample = 4;
            dNumChannels = floor(stHeader.dNumBytesData/dNumBytesPerSample);
            result = zeros(1, dNumChannels);
            index = 1; 
            for n = 1 : dNumChannels
                u8DataOfChan = u8Data(index:index+3);
                binDataOfChan = this.int8ToBin(u8DataOfChan);
                index = index+4;
                result(n) = ieee.IeeeUtils.bin32ToNumMulti(binDataOfChan);
            end

            % Reset tic and update cache
            this.ticGetVariables = tic();
            this.dScanData = result;
            this.lIsBusy = false;
            this.dNumOfSequentialGetScanDataErrors = 0;

        end
        
        

        % Configures either the time period of each scan, in the number of seconds per scan
        function setScanPeriod(this, dSeconds)
           cCmd = sprintf('CONF:SCA:RAT %1.1f', dSeconds);
           this.writeAscii(cCmd);
        end
        
               
        
        
        function setWrapModeOfBufferToWrap(this)
            this.writeAscii(':AD:BUFF:MODE WRA');
        end
        
        function setWrapModeOfBufferToNoWrap(this)
            this.writeAscii(':AD:BUFF:MODE NOWRA');
        end
        
        function setWrapModeOfBufferToDefault(this)
            this.writeAscii(':AD:BUFF:MODE DEF');
        end
        
        
        %------------ TESTED below this line ------------%
        
        
        % If you are using the software (IMMediate) trigger source and have
        % armed the analog input subsystem, you must start the analog input
        % operation by issuing the AD:INITiate command.
        function initiateScan(this)
            this.writeAscii(':AD:INIT');
        end

        % Stops a continuous scan operation on the instrument, if it is in progress.
        function abortScan(this)
            this.writeAscii(':AD:ABOR');
        end
        
        % Sets sampling frequency to max value of 4800 Hz
        function setSamplingFrequencyToMax(this)
            this.writeAscii(':AD:CLOC:FREQ:CONF MAX'); 
        end
        
        % Sets sampling frequency to min value of 1.175 Hz
        function setSamplingFrequencyToMin(this)
            this.writeAscii(':AD:CLOC:FREQ:CONF MIN'); 
        end
        
        function setSamplingFrequency(this, dVal)
            cCmd = sprintf(':AD:CLOC:FREQ:CONF %1.0d', dVal);
            this.writeAscii(cCmd); 
        end
        
        % Returns the sampling frequency in Hz
        function [d, lSuccess] = getSamplingFrequency(this)
            [c, lSuccess] = this.queryAscii(':AD:CLOC:FREQ?');
            d = str2double(c);
        end
        
        function [c, lSuccess] = getWrapModeOfBuffer(this)
            [c, lSuccess] = this.queryAscii(':AD:BUFF:MODE?');
        end
        
        %On power up, the SCPI password-protected commands are disabled. If
        %the instrument is powered down, you must enable the
        %password-protected commands when the instrument is powered back up
        %if you want to configure or operate the instrument.
        
        function enablePasswordProtectedCommands(this)
            cCmd = ':SYST:PASS:CEN admin';
            this.writeAscii(cCmd);
        end
        
        % Returns whether password-protected commands are enabled or disabled.
        function [l, lSuccess] = getPasswordProtectedCommandsEnabled(this)
            cCmd = 'SYST:PASS:CEN:STAT?';
            [c, lSuccess] = this.queryAscii(cCmd); % returns '0' or '1'
            l = logical(str2double(c));
        end
        
        
        function [c, lSuccess] = getIdentity(this)
            cCmd = '*IDN?';
            [c, lSuccess] = this.queryAscii(cCmd);
        end
        
        function armSystem(this)
            this.writeAscii(':AD:ARM');
        end
        
        function [st, lSuccess] = getStatus(this)
            [c, lSuccess] = this.queryAscii(':AD:STAT?');
            % returns ASCII string between '0' and '255' that
            % represents a byte. Convert to binary 8-char string. Each bit is a flag
            % bit 0 - active?
            % bit 1 - armed?
            % bit 2 - triggered?
            % bit 3 - AD SYNC
            % bit 4 - AD FIFO
            % convert to binary string
            cFlags = dec2bin(str2double(c), 8); % e.g., '00001100'
            lFlags = logical(cFlags - '0'); % cute trick https://www.mathworks.com/matlabcentral/answers/89526-binary-string-to-vector
            st = struct();
            st.active = lFlags(end);
            st.armed = lFlags(end-1);
            st.triggered = lFlags(end - 2);
            st.adSync = lFlags(end - 3);
            st.adFifo = lFlags(end - 4);
        end
        
        %  Returns the indices of the chronologically oldest and most recent
        %  scan records in the circular buffer on the instrument.
        function [dIndexStart, dIndexEnd] = getIndicesOfScanBuffer(this)

            % FIX me, add support for returning lError
            try
                c = this.queryAscii(':AD:STAT:SCA?');
                ceVals = strsplit(c, ',');
                if length(ceVals) == 1
                    % there was an error, send out the last good values
                    dIndexStart = this.dIndexStart;
                    dIndexEnd = this.dIndexEnd;
                else
                    dIndexStart = str2num(ceVals{1});
                    dIndexEnd = str2num(ceVals{2});

                    % Update last good values
                    this.dIndexStart = dIndexStart;
                    this.dIndexEnd = dIndexEnd;

                end
            catch mE
               dIndexStart = this.dIndexStart;
               dIndexEnd = this.dIndexEnd;
            end

        end
        
        % Enables a list of channels to scan on the instrument.
        % {u8 1xm} channels - a list of channels to have the hardware scan
        % and store in internal buffer for fast retrieval 
        function enableChannels(this, u8Channels)
            cList = sprintf('%u,', u8Channels);
            cList = cList(1:end - 1); % remove final comma
            cQuery = sprintf(':AD:ENAB 1, (@%s)', cList);
            this.writeAscii(cQuery);
        end
        
        function disableChannels(this, u8Channels)
            cList = sprintf('%u,', u8Channels);
            cList = cList(1:end - 1); % remove final comma
            cQuery = sprintf(':AD:ENAB 0, (@%s)', cList);
            this.writeAscii(cQuery);
        end

        function enableAllChannels(this)
            this.enableChannels(1:4);
        end
        
        function disableAllChannels(this)
            this.disableChannels(1:4);
        end
        
        function [c, lSuccess] = getEnabledChannels(this)
            [c, lSuccess] = this.queryAscii('AD:ENAB?');
        end
        

        % Returns the maximum number of scans that can be stored in the
        % input buffer based on the number of enabled input channels and
        % the input sampling rate.
        function [c, lSuccess] = getSizeOfScanBuffer(this)
            [c, lSuccess] = this.queryAscii(':AD:BUFF:SIZ?');
        end
        
        
    end
    
    
    methods (Access = private)
        
       
        
            
        
        
    end
    
end

