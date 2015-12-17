import upyun.d;
import std.stdio;

void main() {
    UpYunConfig config = UpYunConfig ("test", "test");
    auto yun = createUpYun(config);
    int statusCode;
    auto r = yun.makeDir("/xindong-game-hs/1", true, statusCode);
    writefln("%s %s", r, statusCode);
}
