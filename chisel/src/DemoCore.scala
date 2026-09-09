import chisel3._
import net.gamebub.framework.Core
import net.gamebub.framework.interface._

class DemoCore extends Module with Core {
    val mmcmVcoHz = 800_000_000
    val (displayClockMin, _) = ClocksV0.getClockDisplayHz(1.0 / 60.0)
    val displayDivider = (mmcmVcoHz.toFloat / displayClockMin).floor.toInt
    val displayClock = mmcmVcoHz / displayDivider

    val io = IO(new Bundle {
        val clocks = new ClocksV0(
            clockSystemHz = 10_000_000,
            clockDisplayHz = displayClock,
            clockSpiHz = 200_000_000,
        )
        val video = new VideoV0(
            videoWidth = 240,
            videoHeight = 160,
            colorDepthR = 5,
            colorDepthG = 5,
            colorDepthB = 5,
            framePeriod = 1.0 / 60.0,
        )
        val audio = new AudioV0()
        val host = new HostV0()
        val input = new InputV0()
    })

    bindExtModule("demo_core", io, Map(
        "DISPLAY_DIVIDER" -> displayDivider,
    ))
}
