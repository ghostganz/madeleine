
class FileService

  def open(*args)
    super(*args)
  end

  def exist?(name)
    File.exist?(name)
  end

  def dir_entries(name)
    Dir.entries(name)
  end

  

end
