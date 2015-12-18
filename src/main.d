import upyun.d;
import std.stdio;

void main() {
    UpYunConfig config = UpYunConfig ("test", "test");
    auto yun = createUpYun(config);
    {
        auto r = yun.makeDir("/xindong-game-hs/1", true);
        writefln("%s", r);
    }
    {
        auto r = yun.uploadFile("/xindong-game-hs/1/1", "123.dat", true);
        writefln("%s", r);
    }
    {
        string type; ulong size, ts;
        auto r = yun.fileInfo("/xindong-game-hs/1/1", type, size, ts);
        writefln("%s %s %s %s", r, type, size, ts);
    }
    {
        auto r = yun.deleteFile("/xindong-game-hs/1/1");
        writefln("%s", r);
    }
    {
        auto r = yun.deleteFile("/xindong-game-hs/1");
        writefln("%s", r);
    }
    {
       auto r = yun.downloadFile("/xindong-game-hs/1/1", "1234.dat");
        writefln("%s", r);
    }
    {
        ulong bytes;
        auto r = yun.getUsage("/xindong-game-hs/", bytes);
        writefln("%s %s", r, bytes);
    }
    {
        UpYunFileInfo[] files;
        auto r = yun.listDir("/xindong-game-hs/", files);
        writefln("%s %s", r, files);
    }
}
