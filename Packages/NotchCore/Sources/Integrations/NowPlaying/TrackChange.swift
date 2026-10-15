extension NowPlayingInfo {
    /// Başka bir parçaya geçildi mi: başlık ya da sanatçı değişti ve çalıyor. Oynat/duraklat, konum
    /// ve kapak güncellemesi sayılmaz; ilk görünme (önceki yok) de sayılmaz, açılışta bildirim çıkmasın.
    public static func isTrackChange(from old: NowPlayingInfo?, to new: NowPlayingInfo?) -> Bool {
        guard let old, let new, new.isPlaying else { return false }
        return old.title != new.title || old.artist != new.artist
    }
}
